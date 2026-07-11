#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\capture\screen_capture.ahk
#Include ..\detectors\combat_hud_detector.ahk

if (A_Args.Length < 1) {
    FileAppend("usage: combat_screenshot_test.ahk <screenshot.png> [client-top]`n", "*")
    ExitApp(2)
}

imageCapture := ScreenCapture.LoadImagePixels(A_Args[1])
if !imageCapture["ok"] {
    FileAppend("load failed: " imageCapture["error"] "`n", "*")
    ExitApp(1)
}
clientTop := A_Args.Length >= 2 ? ToInt(A_Args[2], 0) : 0
clientRect := Map(
    "x", 0,
    "y", clientTop,
    "w", imageCapture["w"],
    "h", imageCapture["h"] - clientTop
)
result := CombatHudDetector.Detect(Map(), clientRect, imageCapture)
output := "matched=" result["matched"]
output .= " anchors=" result["anchor_hits"]
output .= " ready=" result["ready_raw"]
output .= " hp=" result["hp_percent"]
output .= " shield=" result["shield_percent"]
output .= " latency=" result["latency_ms"] "ms`n"
outputPath := A_Args.Length >= 3 ? A_Args[3] : A_Temp "\combat-screenshot-result.txt"
try FileDelete(outputPath)
FileAppend(output, outputPath, "UTF-8")
if !result["matched"] || !result["ready_raw"]
    ExitApp(1)
if (result["hp_percent"] = "" || result["hp_percent"] < 55 || result["hp_percent"] > 65)
    ExitApp(1)
if (result["shield_percent"] = "" || result["shield_percent"] < 95)
    ExitApp(1)
ExitApp(0)
