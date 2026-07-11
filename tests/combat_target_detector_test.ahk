#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\capture\screen_capture.ahk
#Include ..\detectors\combat_hud_detector.ahk

imageCapture := NewCapture(1000, 800)
region := Map("x", 80, "y", 160, "w", 840, "h", 464)

DrawDirectionArrow(imageCapture, region)
direction := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, region)
AssertPresence(direction, "ABSENT", "direction arrow")

ClearCapture(imageCapture)
DrawEnemyMarker(imageCapture, region, 0.50, 0.48)
centered := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, region)
AssertPresence(centered, "PRESENT", "centered enemy marker")

ClearCapture(imageCapture)
DrawEnemyMarker(imageCapture, region, 0.72, 0.36)
offCenter := CombatHudDetector.AnalyzeTargetMarkers(imageCapture, region)
AssertPresence(offCenter, "PRESENT", "off-center enemy marker")

ClearCapture(imageCapture)
lockRegion := Map("x", 380, "y", 240, "w", 240, "h", 336)
if (CombatHudDetector.DetectLockBrackets(imageCapture, lockRegion) != "UNLOCKED")
    ExitApp(1)
DrawLockBrackets(imageCapture, lockRegion)
if (CombatHudDetector.DetectLockBrackets(imageCapture, lockRegion) != "LOCKED")
    ExitApp(1)

ExitApp(0)

NewCapture(width, height) {
    bits := Buffer(width * height * 4, 0)
    return Map("ok", true, "error", "", "x", 0, "y", 0, "w", width, "h", height, "stride", width * 4, "bits", bits)
}

ClearCapture(imageCapture) {
    DllCall("RtlZeroMemory", "Ptr", imageCapture["bits"].Ptr, "UPtr", imageCapture["bits"].Size)
}

DrawDirectionArrow(imageCapture, region) {
    x := region["x"] + Round(region["w"] * 0.48)
    y := region["y"] + Round(region["h"] * 0.25)
    FillRegion(imageCapture, Map("x", x, "y", y, "w", 70, "h", 3), 230, 40, 40)
    FillRegion(imageCapture, Map("x", x, "y", y + 14, "w", 70, "h", 3), 230, 40, 40)
    FillRegion(imageCapture, Map("x", x + 60, "y", y, "w", 3, "h", 90), 230, 40, 40)
}

DrawEnemyMarker(imageCapture, region, centerXRatio, centerYRatio) {
    width := Round(region["w"] * 0.08)
    left := region["x"] + Round(region["w"] * centerXRatio - width / 2)
    top := region["y"] + Round(region["h"] * centerYRatio - 8)
    FillRegion(imageCapture, Map("x", left, "y", top, "w", width, "h", 3), 230, 40, 40)
    FillRegion(imageCapture, Map("x", left, "y", top + 16, "w", width, "h", 3), 230, 40, 40)
    FillRegion(imageCapture, Map("x", left + 10, "y", top - 18, "w", 28, "h", 6), 230, 40, 40)
    FillRegion(imageCapture, Map("x", left + 18, "y", top + 24, "w", 8, "h", 8), 230, 40, 40)
    FillRegion(imageCapture, Map("x", left + 36, "y", top + 24, "w", 8, "h", 8), 230, 40, 40)
}

DrawLockBrackets(imageCapture, region) {
    left := region["x"] + Round(region["w"] * 0.28)
    right := region["x"] + Round(region["w"] * 0.70)
    top := region["y"] + Round(region["h"] * 0.30)
    height := Round(region["h"] * 0.38)
    FillRegion(imageCapture, Map("x", left, "y", top, "w", 5, "h", height), 120, 230, 120)
    FillRegion(imageCapture, Map("x", right, "y", top, "w", 5, "h", height), 120, 230, 120)
    FillRegion(imageCapture, Map("x", left, "y", top, "w", 28, "h", 5), 120, 230, 120)
    FillRegion(imageCapture, Map("x", right - 24, "y", top, "w", 28, "h", 5), 120, 230, 120)
}

FillRegion(imageCapture, region, r, g, b) {
    x1 := Max(0, region["x"] - imageCapture["x"])
    y1 := Max(0, region["y"] - imageCapture["y"])
    x2 := Min(imageCapture["w"] - 1, x1 + region["w"] - 1)
    y2 := Min(imageCapture["h"] - 1, y1 + region["h"] - 1)
    y := y1
    while (y <= y2) {
        x := x1
        while (x <= x2) {
            offset := y * imageCapture["stride"] + x * 4
            NumPut("UChar", b, imageCapture["bits"], offset)
            NumPut("UChar", g, imageCapture["bits"], offset + 1)
            NumPut("UChar", r, imageCapture["bits"], offset + 2)
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
