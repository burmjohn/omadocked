import QtQml
import Quickshell
import "../core/GestureLogic.js" as Gestures

// Fixed, inspected shell actions only. No user-controlled command interpolation.
QtObject {
    property bool enabled: true
    function perform(kind: string, delta: real): bool {
        if (!enabled) return false;
        const decision = Gestures.settingsLogoGesture(kind, delta);
        let argv = [];
        if (decision.action === "quick-menu") argv = ["omarchy-menu", "toggle", "root"];
        else if (decision.action === "terminal") argv = ["omarchy-launch-terminal"];
        else if (decision.action === "workspace") {
            // The installed Hyprland 0.56 Lua API and Omadock use this exact selector.
            argv = ["hyprctl", "eval", decision.target === "e+1"
                ? 'hl.dsp.focus({ workspace = "e+1" })'
                : 'hl.dsp.focus({ workspace = "e-1" })'];
        } else return false;
        Quickshell.execDetached(argv);
        return true; // Request submitted, not compositor/application acknowledgement.
    }
}
