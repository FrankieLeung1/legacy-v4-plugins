import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property bool hideIfNoDeviceConnected: cfg.hideIfNoDeviceConnected ?? defaults.hideIfNoDeviceConnected ?? false
  property bool keepBatteryExpanded: cfg.keepBatteryExpanded ?? defaults.keepBatteryExpanded ?? false

  spacing: Style.marginL

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NToggle {
        label: pluginApi?.tr("settings.no-device-connected-hide.label")
        description: pluginApi?.tr("settings.no-device-connected-hide.description")

        checked: root.hideIfNoDeviceConnected
        onToggled: function(checked) {
            root.hideIfNoDeviceConnected = checked
        }
    }

    NToggle {
        label: pluginApi?.tr("settings.keep-battery-expanded.label")
        description: pluginApi?.tr("settings.keep-battery-expanded.description")

        checked: root.keepBatteryExpanded
        onToggled: function(checked) {
            root.keepBatteryExpanded = checked
        }
    }
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("KDEConnect", "Cannot save settings: pluginApi is null");
      return;
    }

    pluginApi.pluginSettings.hideIfNoDeviceConnected = root.hideIfNoDeviceConnected;
    pluginApi.pluginSettings.keepBatteryExpanded = root.keepBatteryExpanded;
    pluginApi.saveSettings();

    Logger.d("KDEConnect", "Settings saved successfully");
  }
}