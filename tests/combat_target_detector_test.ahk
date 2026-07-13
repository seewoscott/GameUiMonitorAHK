#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\capture\screen_capture.ahk
#Include ..\detectors\combat_hud_detector.ahk

for _, dimensions in [[1024, 768], [2048, 1536]] {
    width := dimensions[1]
    height := dimensions[2]
    imageCapture := NewCapture(width, height)
    clientRect := Map("x", 0, "y", 0, "w", width, "h", height)
    regions := CombatHudDetector.BuildRegions(clientRect)
    scale := CombatHudDetector.BuildSamplingScale(clientRect)
    targetRegion := regions["target"]
    lockRegion := regions["lock"]
    labelPrefix := width "x" height " "

    empty := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, targetRegion, scale["x"], scale["y"])
    AssertPresence(empty, "ABSENT", labelPrefix "empty frame")

    DrawDirectionArrow(imageCapture, targetRegion, scale["x"], scale["y"])
    direction := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, targetRegion, scale["x"], scale["y"])
    AssertPresence(direction, "ABSENT", labelPrefix "direction arrow")

    ClearCapture(imageCapture)
    DrawEnemyMarker(imageCapture, targetRegion, 0.50, 0.48, scale["x"], scale["y"])
    centered := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, targetRegion, scale["x"], scale["y"])
    AssertPresence(centered, "PRESENT", labelPrefix "centered enemy marker")

    ClearCapture(imageCapture)
    DrawEnemyMarker(imageCapture, targetRegion, 0.72, 0.36, scale["x"], scale["y"])
    offCenter := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, targetRegion, scale["x"], scale["y"])
    AssertPresence(offCenter, "PRESENT", labelPrefix "off-center enemy marker")

    ClearCapture(imageCapture)
    if (CombatHudDetector.DetectLockBrackets(imageCapture, lockRegion, scale["x"], scale["y"]) != "UNLOCKED")
        ExitApp(1)
    DrawSingleLockBracket(imageCapture, lockRegion, scale["x"], scale["y"])
    if (CombatHudDetector.DetectLockBrackets(imageCapture, lockRegion, scale["x"], scale["y"]) != "UNLOCKED")
        ExitApp(1)
    ClearCapture(imageCapture)
    DrawLockBrackets(imageCapture, lockRegion, scale["x"], scale["y"])
    if (CombatHudDetector.DetectLockBrackets(imageCapture, lockRegion, scale["x"], scale["y"]) != "LOCKED")
        ExitApp(1)
}

ExitApp(0)

NewCapture(width, height) {
    bits := Buffer(width * height * 4, 0)
    return Map("ok", true, "error", "", "x", 0, "y", 0, "w", width, "h", height, "stride", width * 4, "bits", bits)
}

ClearCapture(capture) {
    DllCall("RtlZeroMemory", "Ptr", capture["bits"].Ptr, "UPtr", capture["bits"].Size)
}

DrawDirectionArrow(capture, region, scaleX, scaleY) {
    x := region["x"] + Round(region["w"] * 0.48)
    y := region["y"] + Round(region["h"] * 0.25)
    lineW := Round(70 * scaleX)
    lineH := Max(1, Round(3 * scaleY))
    FillRegion(capture, Map("x", x, "y", y, "w", lineW, "h", lineH), 230, 40, 40)
    FillRegion(capture, Map("x", x, "y", y + Round(14 * scaleY), "w", lineW, "h", lineH), 230, 40, 40)
    FillRegion(capture, Map("x", x + Round(35 * scaleX), "y", y, "w", Max(1, Round(3 * scaleX)), "h", Round(90 * scaleY)), 230, 40, 40)
}

DrawEnemyMarker(capture, region, centerXRatio, centerYRatio, scaleX, scaleY) {
    width := Round(region["w"] * 0.08)
    left := region["x"] + Round(region["w"] * centerXRatio - width / 2)
    top := region["y"] + Round(region["h"] * centerYRatio - 8 * scaleY)
    lineH := Max(1, Round(3 * scaleY))
    FillRegion(capture, Map("x", left, "y", top, "w", width, "h", lineH), 230, 40, 40)
    FillRegion(capture, Map("x", left, "y", top + Round(16 * scaleY), "w", width, "h", lineH), 230, 40, 40)
    FillRegion(capture, Map("x", left + Round(10 * scaleX), "y", top - Round(18 * scaleY), "w", Round(28 * scaleX), "h", Round(6 * scaleY)), 230, 40, 40)
    FillRegion(capture, Map("x", left + Round(18 * scaleX), "y", top + Round(24 * scaleY), "w", Round(8 * scaleX), "h", Round(8 * scaleY)), 230, 40, 40)
    FillRegion(capture, Map("x", left + Round(36 * scaleX), "y", top + Round(24 * scaleY), "w", Round(8 * scaleX), "h", Round(8 * scaleY)), 230, 40, 40)
}

DrawSingleLockBracket(capture, region, scaleX, scaleY) {
    left := region["x"] + Round(region["w"] * 0.28)
    top := region["y"] + Round(region["h"] * 0.30)
    height := Round(region["h"] * 0.38)
    FillRegion(capture, Map("x", left, "y", top, "w", Max(1, Round(5 * scaleX)), "h", height), 120, 230, 120)
    FillRegion(capture, Map("x", left, "y", top, "w", Round(28 * scaleX), "h", Max(1, Round(5 * scaleY))), 120, 230, 120)
}

DrawLockBrackets(capture, region, scaleX, scaleY) {
    DrawSingleLockBracket(capture, region, scaleX, scaleY)
    right := region["x"] + Round(region["w"] * 0.70)
    top := region["y"] + Round(region["h"] * 0.30)
    height := Round(region["h"] * 0.38)
    FillRegion(capture, Map("x", right, "y", top, "w", Max(1, Round(5 * scaleX)), "h", height), 120, 230, 120)
    FillRegion(capture, Map("x", right - Round(24 * scaleX), "y", top, "w", Round(28 * scaleX), "h", Max(1, Round(5 * scaleY))), 120, 230, 120)
}

FillRegion(capture, region, r, g, b) {
    x1 := Max(0, Round(region["x"] - capture["x"]))
    y1 := Max(0, Round(region["y"] - capture["y"]))
    x2 := Min(capture["w"] - 1, x1 + Max(1, Round(region["w"])) - 1)
    y2 := Min(capture["h"] - 1, y1 + Max(1, Round(region["h"])) - 1)
    y := y1
    while (y <= y2) {
        x := x1
        while (x <= x2) {
            offset := y * capture["stride"] + x * 4
            NumPut("UChar", b, capture["bits"], offset)
            NumPut("UChar", g, capture["bits"], offset + 1)
            NumPut("UChar", r, capture["bits"], offset + 2)
            x += 1
        }
        y += 1
    }
}

AssertPresence(result, expectedPresence, label) {
    if (result["presence"] != expectedPresence) {
        FileAppend(
            label ": expected " expectedPresence
            ", got " result["presence"]
            ", count=" result["count"] ", score=" result["lock_score"] "`n",
            "*"
        )
        ExitApp(1)
    }
}
