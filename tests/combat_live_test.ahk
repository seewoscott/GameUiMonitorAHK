#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\core\config.ahk
#Include ..\core\window.ahk
#Include ..\capture\screen_capture.ahk
#Include ..\detectors\combat_hud_detector.ahk

root := RegExReplace(A_ScriptDir, "\\tests$")
cfg := MonitorConfig.Load(root)
window := WindowManager(cfg, LiveTestLogger())
if !window.FindTarget(false)
    ExitApp(2)
clientRect := window.GetTargetClientRect()
result := CombatHudDetector.Detect(Map(), clientRect)
output := "client=[" clientRect["x"] "," clientRect["y"] "," clientRect["w"] "," clientRect["h"] "]"
output .= " matched=" result["matched"]
output .= " anchors=" result["anchor_hits"]
output .= " ready=" result["ready_raw"]
output .= " hp=" result["hp_percent"]
output .= " shield=" result["shield_percent"]
output .= " latency=" result["latency_ms"] "ms`n"
outputPath := A_Args.Length >= 1 ? A_Args[1] : A_Temp "\combat-live-result.txt"
try FileDelete(outputPath)
FileAppend(output, outputPath, "UTF-8")
ExitApp(result["latency_ms"] <= 500 ? 0 : 1)

class LiveTestLogger {
    Warn(*) {
    }
}
