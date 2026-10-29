import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Power Profile")
    toggled: PowerProfilesDaemon.activeProfile !== "balanced"
    icon: PowerProfilesDaemon.icon
    statusText: PowerProfilesDaemon.displayName
    
    mainAction: () => {
        PowerProfilesDaemon.cycleNext();
    }
    tooltipText: Translation.tr("Click to cycle through power profiles")
}
