import QtQuick
import Quickshell.Io
import "../core/ParitySettings.js" as Parity

// One bounded player above all outputs. No automatic samples or queued sounds.
QtObject {
    id: root
    property bool allowed: false
    property string _player: ""
    property string status: "checking"
    property bool _active: false
    property bool _cancelled: false
    readonly property bool busy: _active || playback.running
    function _cancel() {
        if (!busy || _cancelled) return;
        _cancelled = true;
        if (playback.running) {
            playback.signal(15);
            killDeadline.restart();
        }
    }
    function _finish(code) {
        // No new child until exit; ignore duplicate/late terminal callbacks.
        if (!_active || playback.running) return;
        _active = false;
        killDeadline.stop();
        deadline.stop();
        launchDeadline.stop();
        if (!_cancelled && status === "available" && code !== 0)
            status = "unavailable: sound playback failed";
    }
    function play(name) {
        if (!allowed || status !== "available" || busy || cooldown.running || name === "none" || Parity.soundNames.indexOf(name) < 0)
            return false;
        playback.command = [_player, "--id", name, "--loop", "1"];
        _active = true;
        _cancelled = false;
        status = "starting";
        launchDeadline.restart();
        deadline.restart();
        playback.running = true;
        cooldown.start();
        return true;
    }
    onAllowedChanged: if (!allowed)
        _cancel()
    property Process discovery: Process {
        // Static command, no user values. Resolve once per service lifetime.
        command: ["sh", "-c", "command -v canberra-gtk-play"]
        running: true
        stdout: StdioCollector {
            id: discovered
        }
        onExited: code => {
            const path = discovered.text.trim();
            root._player = code === 0 && path.startsWith("/") ? path : "";
            root.status = root._player ? "available" : "unavailable: canberra-gtk-play missing";
        }
    }
    property Process playback: Process {
        onStarted: {
            root.launchDeadline.stop();
            if (root.status === "starting") root.status = "available";
            if (root._cancelled || !root.allowed) root.playback.signal(9);
        }
        onExited: code => root._finish(code)
    }
    // Installed Process has started/exited, but no failed-start signal.
    // A request is busy until acknowledgement or this bounded check.
    property Timer launchDeadline: Timer {
        interval: 500
        onTriggered: {
            root.status = "unavailable: sound player failed to start";
            root._cancelled = true;
            if (root.playback.running) root.playback.signal(9);
            else root._finish(1);
        }
    }
    // Same exact-child escalation as AppService's configuration lifecycle.
    // Best effort for userspace resistance, not uninterruptible kernel I/O.
    property Timer killDeadline: Timer {
        interval: 500
        onTriggered: if (root.playback.running) root.playback.signal(9)
    }
    property Timer deadline: Timer {
        interval: 2000
        onTriggered: {
            root.status = "unavailable: sound playback timed out";
            root._cancelled = true;
            if (root.playback.running) root.playback.signal(9);
            else root._finish(1);
        }
    }
    property Timer cooldown: Timer {
        interval: 2000
    }
    Component.onDestruction: {
        // Timers cannot outlive this owner. Kill only its current child.
        if (playback.running) playback.signal(9);
        discovery.running = false;
    }
}
