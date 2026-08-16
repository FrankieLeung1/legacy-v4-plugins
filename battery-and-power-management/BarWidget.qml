import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen: null
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property string screenName: screen ? (screen.name ?? "") : ""
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(root.screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(root.screenName)
    readonly property string fixedFont: Settings.data?.ui?.fontFixed ?? "monospace"

    property color profileBackgroundColor: {
        if (mouseArea.containsMouse) {
            return Color.mHover;
        }

        if (root.batStatus === pluginApi.tr("battery.status-charging")) {
            return Color.mPrimary;
        }

        if (root.colorizeByProfile) {
            if (root.currentProfile === "power-saver") return root.colorPowerSaver;
            if (root.currentProfile === "performance") return root.colorPerformance;
        }

        return Style.capsuleColor;
    }

    property color profileForegroundColor: {
        if (mouseArea.containsMouse || root.batStatus === pluginApi.tr("battery.status-charging")) {
            return Color.mOnPrimary;
        }
        
        if (root.colorizeByProfile && (root.currentProfile === "power-saver" || root.currentProfile === "performance")) {
            return Color.mOnPrimary;
        }
        
        return Color.mOnSurface;
}

    property int batPercent: 0
    property real wattNum: 0.0
    property string batStatus: pluginApi.tr("battery.status-unknown")
    property string timeRemaining: "..."
    
    property string currentProfile: "balanced"
    property int batteryThreshold: 80
    property bool hasStandardThreshold: false
    property bool hasConservationMode: false
    property bool conservationMode: false
    property string conservationFilePath: "/sys/class/power_supply/BAT1/extensions/ideapad_laptop/conservation_mode"
    property string thresholdFilePath: "/sys/class/power_supply/BAT1/charge_control_end_threshold"

    readonly property real contentWidth: layout.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight
    implicitWidth: contentWidth
    implicitHeight: Style.barHeight

    property bool colorizeByProfile:
        pluginApi?.pluginSettings?.colorizeByProfile ??
        pluginApi?.manifest?.metadata?.defaultSettings?.colorizeByProfile ??
        true

    property string colorPowerSaver:
        pluginApi?.pluginSettings?.colorPowerSaver ??
        pluginApi?.manifest?.metadata?.defaultSettings?.colorPowerSaver ??
        Color.mSecondary

    property string colorPerformance:
        pluginApi?.pluginSettings?.colorPerformance ??
        pluginApi?.manifest?.metadata?.defaultSettings?.colorPerformance ??
        Color.mError

    property bool showProfile:
        pluginApi?.pluginSettings?.showProfile ??
        pluginApi?.manifest?.metadata?.defaultSettings?.showProfile ??
        true

    property bool showBalancedIcon:
        pluginApi?.pluginSettings?.showBalancedIcon  ??
        pluginApi?.manifest?.metadata?.defaultSettings?.showBalancedIcon ??
        false

    function getBatteryIcon() {
        if (root.batStatus === pluginApi.tr("battery.status-charging")) {
            return "battery-charging";
        }
        if (root.batStatus === pluginApi.tr("battery.status-full")) {
            return "battery-charging-2";
        }
        
        if (root.batPercent >= 86) return "battery-4";
        if (root.batPercent >= 56) return "battery-3";
        if (root.batPercent >= 31) return "battery-2";
        if (root.batPercent >= 11) return "battery-1";
        return "battery";
    }

    // ===== Helpers =====

    function parseEta(out) {
        if (!out) return "...";
        let lines = out.split("\n");
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (line.indexOf("time to empty:") === 0 || line.indexOf("time to full:") === 0) {
                let value = line.substring(line.indexOf(":") + 1).trim();
                return formatUpowerTime(value);
            }
        }
        return "...";
    }

    function formatUpowerTime(value) {
        let parts = value.split(/\s+/);
        let num = parseFloat(parts[0]);
        let unit = parts.length > 1 ? parts[1] : "";
        if (isNaN(num)) return "...";
        let minutes = 0;
        if (unit.indexOf("hour") === 0) minutes = num * 60;
        else if (unit.indexOf("minute") === 0) minutes = num;
        else if (unit.indexOf("second") === 0) minutes = num / 60;
        else if (unit.indexOf("day") === 0) minutes = num * 1440;
        else return value;
        let total = Math.round(minutes);
        let h = Math.floor(total / 60);
        let m = total % 60;
        return h > 0 ? (h + "h " + m + "m") : (m + "m");
    }

    // ===== Power Profiles =====

    Process {
        id: profileGetter
        command: ["powerprofilesctl", "get"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                root.currentProfile = data.trim();
            }
        }
    }

    Process {
        id: profileSetter
        running: false
    }

    function updatePowerProfile() {
        profileGetter.running = true;
    }

    function setPowerProfile(profile) {
        profileSetter.command = ["powerprofilesctl", "set", profile];
        profileSetter.running = true;
        root.currentProfile = profile;
    }

    Component.onCompleted: {
        if (pluginApi) {
            pluginApi.mainInstance = root;
        }
        hardwareDetector.running = true;
        updatePowerProfile();
    }

    // ===== Battery & Conservation Logic =====

    Process {
        id: hardwareDetector
        running: false
        command: ["sh", "-c", "bat='BAT0'; [ -d /sys/class/power_supply/BAT1 ] && bat='BAT1'; cons=''; if [ -f /sys/class/power_supply/$bat/extensions/ideapad_laptop/conservation_mode ]; then cons=/sys/class/power_supply/$bat/extensions/ideapad_laptop/conservation_mode; elif [ -f /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode ]; then cons=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode; fi; thresh=''; [ -f /sys/class/power_supply/$bat/charge_control_end_threshold ] && thresh=/sys/class/power_supply/$bat/charge_control_end_threshold; echo \"$bat|$thresh|$cons\""]
        stdout: StdioCollector {
            onStreamFinished: {
                let out = text.trim();
                if (!out) return;
                let parts = out.split("|");
                let dev = parts[0] || "BAT1";
                let thresh = parts[1] || "";
                let cons = parts[2] || "";

                batLoader.device = dev;
                if (thresh) {
                    root.hasStandardThreshold = true;
                    root.thresholdFilePath = thresh;
                    thresholdLoader.path = thresh;
                }
                if (cons) {
                    root.hasConservationMode = true;
                    root.conservationFilePath = cons;
                    ideapadConservationLoader.path = cons;
                }
                batLoader.reload();
                if (thresh) thresholdLoader.reload();
                if (cons) ideapadConservationLoader.reload();
            }
        }
    }

    function setConservationMode(enabled) {
        root.conservationMode = enabled;
        root.batteryThreshold = enabled ? 80 : 100;
        let val = enabled ? 1 : 0;
        let path = root.conservationFilePath || "/sys/class/power_supply/BAT1/extensions/ideapad_laptop/conservation_mode";
        thresholdSetter.running = false;
        thresholdSetter.command = ["sh", "-c", "echo " + val + " > " + path];
        thresholdSetter.running = true;
    }

    function setBatteryThreshold(value) {
        root.batteryThreshold = value;
        thresholdSetter.running = false;
        if (root.hasStandardThreshold) {
            let devPath = root.thresholdFilePath || "/sys/class/power_supply/BAT1/charge_control_end_threshold";
            thresholdSetter.command = ["sh", "-c", "echo " + value + " > " + devPath];
        } else if (root.hasConservationMode) {
            let enabled = value <= 85;
            root.conservationMode = enabled;
            let val = enabled ? 1 : 0;
            let path = root.conservationFilePath || "/sys/class/power_supply/BAT1/extensions/ideapad_laptop/conservation_mode";
            thresholdSetter.command = ["sh", "-c", "echo " + val + " > " + path];
        }
        thresholdSetter.running = true;
    }

    Process {
        id: thresholdSetter
        onExited: (code) => {
            if (code !== 0) {
                Logger.e("BatteryAndPowerManagement", "Error writing battery threshold / conservation mode.");
            } else {
                if (root.hasConservationMode) ideapadConservationLoader.reload();
                if (root.hasStandardThreshold) thresholdLoader.reload();
            }
        }
    }

    // ===== ETA via upower =====

    Process {
        id: etaGetter
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.timeRemaining = root.parseEta(text);
            }
        }
        onExited: (code) => {
            if (code !== 0) {
                root.timeRemaining = "...";
            }
        }
    }

    Timer {
        id: globalRefreshTimer
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            batLoader.reload();
            if (root.hasStandardThreshold) thresholdLoader.reload();
            if (root.hasConservationMode) ideapadConservationLoader.reload();

            let dev = batLoader.device || "BAT1";
            etaGetter.running = false;
            etaGetter.command = ["upower", "-i", "/org/freedesktop/UPower/devices/battery_" + dev];
            etaGetter.running = true;
        }
    }

    FileView {
        id: thresholdLoader
        path: root.thresholdFilePath
        printErrors: false
        onLoaded: {
            let val = text();
            if (val) {
                let parsed = parseInt(val.trim());
                if (!isNaN(parsed) && parsed >= 50 && parsed <= 100) {
                    root.hasStandardThreshold = true;
                    root.batteryThreshold = parsed;
                }
            }
        }
    }

    FileView {
        id: ideapadConservationLoader
        path: root.conservationFilePath
        printErrors: false
        onLoaded: {
            let val = text();
            if (val) {
                let parsed = parseInt(val.trim());
                if (!isNaN(parsed) && (parsed === 0 || parsed === 1)) {
                    root.hasConservationMode = true;
                    root.conservationMode = (parsed === 1);
                    if (!root.hasStandardThreshold) {
                        root.batteryThreshold = (parsed === 1 ? 80 : 100);
                    }
                }
            }
        }
    }

    FileView {
        id: batLoader
        property string device: "BAT1"
        path: "/sys/class/power_supply/" + device + "/uevent"
        printErrors: false

        onLoaded: {
            let content = text();
            if (!content) return;

            let lines = content.split("\n");
            let cap = 0, rate = 0;
            let statusRaw = "Unknown";

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (line.indexOf("POWER_SUPPLY_CAPACITY=") === 0) cap = parseInt(line.split("=")[1]) || 0;
                else if (line.indexOf("POWER_SUPPLY_POWER_NOW=") === 0) rate = parseInt(line.split("=")[1]) || 0;
                else if (line.indexOf("POWER_SUPPLY_STATUS=") === 0) statusRaw = line.split("=")[1] || "Unknown";
            }

            root.batPercent = cap;
            
            if (statusRaw === "Charging") root.batStatus = pluginApi.tr("battery.status-charging");
            else if (statusRaw === "Full") root.batStatus = pluginApi.tr("battery.status-full");
            else if (statusRaw === "Discharging") root.batStatus = pluginApi.tr("battery.status-discharging");
            else if (statusRaw === "Not charging") root.batStatus = pluginApi.tr("battery.status-not-charging");
            else root.batStatus = pluginApi.tr("battery.status-unknown");

            root.wattNum = rate / 1000000.0;
        }
    }

    // ===== UI =====
    Rectangle {
        id: visualCapsule
        anchors.centerIn: parent
        width: root.contentWidth
        height: root.contentHeight
        radius: Style.radiusL
        
        color: mouseArea.containsMouse 
            ? Color.mHover 
            : (root.batStatus === pluginApi.tr("battery.status-charging") ? Color.mPrimary : root.profileBackgroundColor)

        border.color: root.batStatus === pluginApi.tr("battery.status-charging") ? Color.mPrimary : Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        RowLayout {
            id: layout
            anchors.centerIn: parent
            spacing: Style.marginS

            NIcon {
                icon: root.getBatteryIcon()
                color: root.profileForegroundColor
            }

            NText {
                text: root.batPercent + "% " + (root.batStatus === pluginApi.tr("battery.status-charging") ? "+" : "-") + root.wattNum.toFixed(1) + "W"
                pointSize: barFontSize
                font.family: root.fixedFont
                font.weight: Font.Bold
                color: root.profileForegroundColor
            }

            NIcon {
                visible: root.showProfile
                icon: {
                    if (root.currentProfile === "power-saver") return "leaf";
                    if (root.currentProfile === "performance") return "gauge";
                    if (root.showBalancedIcon) return "scale";
                    return "";
                }
                color: root.profileForegroundColor
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton


        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen)
            } else {
                root.updatePowerProfile();
                thresholdLoader.reload();
                pluginApi.openPanel(root.screen, root);
            }
        }
    }

    // ===== CONTEXT MENU ====
    NPopupContextMenu {
        id: contextMenu

        model: [
            {
                "label": pluginApi.tr("settings.widget-settings"),
                "action": "settings",
                "icon": "settings"
            }
        ]

        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(screen)

            if (action === "settings") {
                if (pluginApi?.manifest) {
                    BarService.openPluginSettings(screen, pluginApi.manifest)
                }
            }
        }
    }

    
}
