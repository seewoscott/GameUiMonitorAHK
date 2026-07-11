#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\core\config.ahk
#Include ..\core\logger.ahk
#Include ..\core\window.ahk
#Include ..\capture\screen_capture.ahk
#Include ..\detectors\room_state_detector.ahk

root := RegExReplace(A_ScriptDir, "\\tests$")
cfg := MonitorConfig.Load(root)
window := WindowManager(cfg, RoomSelfLiveLogger())
if !window.FindTarget(false)
    ExitApp(2)
roomElement := ""
for _, element in cfg.elements {
    if (element["id"] = "room_slots") {
        roomElement := element
        break
    }
}
if !IsObject(roomElement)
    ExitApp(2)
region := window.RegionToScreen(roomElement)
result := RoomStateDetector.Detect(roomElement, region)
output := "region=[" region["x"] "," region["y"] "," region["w"] "," region["h"] "]"
output .= " candidate=" result["self_candidate_index"]
output .= " top=" result["self_top_index"]
output .= " margin=" Format("{:.1f}", result["self_candidate_margin"])
output .= " latency=" result["latency_ms"] "ms`n"
for _, slot in result["slots"] {
    if !slot["occupied"]
        continue
    output .= Format("{:02}", slot["index"]) " " slot["state"]
    output .= " top=" Format("{:.2f}", slot["self_border_top"])
    output .= " bottom=" Format("{:.2f}", slot["self_border_bottom"])
    output .= " center=" Format("{:.2f}", slot["self_border_center"])
    output .= " score=" Format("{:.1f}", slot["self_score"])
    output .= " eligible=" slot["self_border_eligible"] "`n"
}
outputPath := A_Args.Length >= 1 ? A_Args[1] : A_Temp "\room-self-live-result.txt"
try FileDelete(outputPath)
FileAppend(output, outputPath, "UTF-8")
ExitApp(result["latency_ms"] <= 500 ? 0 : 1)

class RoomSelfLiveLogger {
    Warn(*) {
    }
}
