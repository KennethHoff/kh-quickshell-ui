// Exec string preparation for kh-launcher.
// Mirrors the inline expressions in launch() and launchToWorkspace() in kh-launcher.nix.
import QtQuick

QtObject {
    // Strip XDG Desktop Entry field codes (%u %U %f %F %d %D %n %N %i %c %k %v %m %%).
    function stripExecCodes(execString) {
        return (execString || "").replace(/%[uUfFdDnNickvm%]/g, "").trim()
    }

    // Build the final exec string, wrapping in terminalBin if entry.runInTerminal is set.
    function buildExec(entry, terminalBin) {
        const exec = stripExecCodes(entry.execString)
        return entry.runInTerminal ? terminalBin + " -- " + exec : exec
    }

    // Prefix exec with a hyprctl workspace dispatch target.
    function workspaceExec(entry, workspace, terminalBin) {
        return "[workspace " + workspace + "] " + buildExec(entry, terminalBin)
    }
}
