#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\core\config.ahk
#Include ..\core\logger.ahk
#Include ..\core\window.ahk
#Include ..\capture\pixel_capture.ahk
#Include ..\capture\screen_capture.ahk
#Include ..\detectors\color_detector.ahk
#Include ..\detectors\image_detector.ahk
#Include ..\detectors\change_detector.ahk
#Include ..\detectors\room_state_detector.ahk
#Include ..\detectors\combat_hud_detector.ahk
#Include ..\core\combat_state.ahk
#Include ..\core\eventbus.ahk
#Include ..\overlay\overlay.ahk
#Include ..\core\scheduler.ahk

AssertCombatGeometry(width, height, expected) {
    regions := CombatHudDetector.BuildRegions(Map("x", 0, "y", 0, "w", width, "h", height))
    for name, values in expected {
        region := regions[name]
        if (region["x"] != values[1] || region["y"] != values[2]
            || region["w"] != values[3] || region["h"] != values[4])
            ExitApp(1)
    }
    if (regions["weapon_slots"].Length != 5)
        ExitApp(1)
    for _, region in regions["weapon_slots"] {
        if (region["x"] < 0 || region["y"] < 0
            || region["x"] + region["w"] > width
            || region["y"] + region["h"] > height)
            ExitApp(1)
    }
    combatOverlay := OverlayManager.PlaceCombatOverlay(Map("x", 0, "y", 0, "w", width, "h", height), 350, 350)
    if (combatOverlay["x"] < 0 || combatOverlay["y"] < 0
        || combatOverlay["x"] + 350 > width || combatOverlay["y"] + 350 > height)
        ExitApp(1)
}

root := RegExReplace(A_ScriptDir, "\\tests$")
cfg := MonitorConfig.Load(root)
cfg.loggingEnabled := false
baseRegion := WindowManager.ScaleRegion(
    Map("region_x", 18, "region_y", 343, "region_w", 310, "region_h", 228),
    Map("x", 0, "y", 0, "w", 1040, "h", 807),
    1040,
    807
)
if (baseRegion["x"] != 18 || baseRegion["y"] != 343 || baseRegion["w"] != 310 || baseRegion["h"] != 228)
    ExitApp(1)
scaledRegion := WindowManager.ScaleRegion(
    Map("region_x", 18, "region_y", 343, "region_w", 310, "region_h", 228),
    Map("x", 0, "y", 0, "w", 2080, "h", 1614),
    1040,
    807
)
if (scaledRegion["x"] != 36 || scaledRegion["y"] != 686 || scaledRegion["w"] != 620 || scaledRegion["h"] != 456)
    ExitApp(1)

for slotIndex in [1, 6, 12] {
    bounds := RoomStateDetector.BuildSlotBounds(scaledRegion, slotIndex, 12)
    expectedY := 686 + (slotIndex - 1) * 38
    if (bounds["y"] != expectedY || bounds["h"] != 38)
        ExitApp(1)
}

slotRegions := RoomStateDetector.BuildSlotRegions(36, 686, 620, 38)
statusRegion := slotRegions["status"]
if (statusRegion["x"] != 526 || statusRegion["y"] != 702 || statusRegion["w"] != 120 || statusRegion["h"] != 5)
    ExitApp(1)

testBits := Buffer(4 * 2 * 4, 0)
for offset in [0, 4] {
    NumPut("UChar", 255, testBits, offset)
    NumPut("UChar", 255, testBits, offset + 1)
    NumPut("UChar", 255, testBits, offset + 2)
}
testCapture := Map("ok", true, "x", 100, "y", 200, "w", 4, "h", 2, "stride", 16, "bits", testBits)
testColorRegion := Map("x", 100, "y", 200, "w", 4, "h", 1)
if (ScreenCapture.CountColorMatches(testCapture, testColorRegion, "0xFFFFFF", 0, 2) != 2)
    ExitApp(1)
if (ScreenCapture.CountColorMatches(testCapture, testColorRegion, "0x00FFFF", 0, 2) != 0)
    ExitApp(1)
whiteChannel := ScreenCapture.SelectSearchChannel(HexToRgb("0xFFFFFF"))
masterChannel := ScreenCapture.SelectSearchChannel(HexToRgb("0x66F603"))
if (whiteChannel["offset"] != 0 || masterChannel["offset"] != 2)
    ExitApp(1)

overlayPosition := OverlayManager.PlaceOutsideRegion(
    scaledRegion,
    620,
    456,
    Map("left", 0, "top", 0, "right", 2080, "bottom", 1614)
)
if (overlayPosition["x"] != 664 || overlayPosition["y"] != 686)
    ExitApp(1)
baseOverlay := OverlayManager.PlaceOutsideRegion(
    baseRegion,
    207,
    228,
    Map("left", 0, "top", 0, "right", 1920, "bottom", 1040)
)
if (baseOverlay["x"] != 336 || baseOverlay["y"] != 343)
    ExitApp(1)
clampedOverlay := OverlayManager.PlaceOutsideRegion(
    Map("x", 900, "y", 700, "w", 100, "h", 100),
    500,
    400,
    Map("left", 100, "top", 50, "right", 1100, "bottom", 850)
)
if (clampedOverlay["x"] < 100 || clampedOverlay["x"] + 500 > 1100
    || clampedOverlay["y"] < 50 || clampedOverlay["y"] + 400 > 850)
    ExitApp(1)

AssertCombatGeometry(1024, 768, Map(
    "left", [20, 15, 190, 81],
    "score", [410, 15, 194, 93],
    "radar", [819, 15, 200, 231],
    "hp", [70, 45, 118, 8],
    "shield", [70, 64, 118, 8],
    "weapons", [251, 664, 532, 104],
    "view", [102, 154, 820, 460],
    "lock", [389, 230, 246, 323],
    "target", [102, 154, 820, 460]
))
AssertCombatGeometry(2048, 1536, Map(
    "left", [41, 31, 379, 161],
    "score", [819, 31, 389, 184],
    "radar", [1638, 31, 400, 461],
    "hp", [139, 89, 238, 17],
    "shield", [139, 127, 238, 17],
    "weapons", [502, 1329, 1065, 207],
    "view", [205, 307, 1638, 922],
    "lock", [778, 461, 492, 645],
    "target", [205, 307, 1638, 922]
))
baseSampling := CombatHudDetector.BuildSamplingScale(Map("w", 1024, "h", 768))
doubleSampling := CombatHudDetector.BuildSamplingScale(Map("w", 2048, "h", 1536))
if (baseSampling["x"] != 1.0 || baseSampling["y"] != 1.0
    || doubleSampling["x"] != 2.0 || doubleSampling["y"] != 2.0)
    ExitApp(1)
if (CombatHudDetector.ScaleSampleStep(10, doubleSampling["x"]) != 20
    || CombatHudDetector.ScaleSampleStep(3, doubleSampling["y"]) != 6)
    ExitApp(1)
logger := MonitorLogger(root, cfg)
logger.Info("自检开始：加载配置与模块。")
if (cfg.elements.Length < 1) {
    logger.Error("自检失败：elements.csv 没有可用元素。")
    ExitApp(1)
}
roomElement := ""
for _, element in cfg.elements {
    if (element["id"] = "room_slots") {
        roomElement := element
        break
    }
}
if !IsObject(roomElement)
    ExitApp(1)
if (roomElement["region_h"] != 228 || roomElement["debounce_ms"] != 500 || roomElement["cooldown_ms"] != 600)
    ExitApp(1)

fakeRegion := Map("x", 0, "y", 0, "w", 10, "h", 10)
bus := MonitorEventBus(cfg, logger)
result := Map("matched", true, "score", 1.0, "color", "0xFFFFFF", "latency_ms", 0, "error", "")
testElement := Map("id", "self_test_event", "lane", "fast", "method", "color", "event_type", "ANY", "cooldown_ms", 0)
bus.Process(testElement, result, fakeRegion)
slots := [
    Map("index", 1, "state", "MASTER", "state_zh", "房主", "occupied", true, "score", 1.0, "region", [0, 0, 10, 10]),
    Map("index", 2, "state", "NOT_READY", "state_zh", "未准备", "occupied", true, "score", 0.86, "region", [0, 10, 10, 10]),
    Map("index", 3, "state", "READY", "state_zh", "已准备", "occupied", true, "score", 1.0, "region", [0, 20, 10, 10])
]
slotResult := Map(
    "matched", true,
    "score", 1.0,
    "color", "",
    "latency_ms", 1,
    "error", "",
    "slots", slots,
    "slot_count", 3,
    "occupied_count", 3,
    "ready_count", 1,
    "master_count", 1,
    "summary_zh", "1号房主，2号未准备，3号已准备"
)
slotElement := Map("id", "self_test_room_slots", "lane", "medium", "method", "room_slots", "event_type", "ANY", "debounce_ms", 0, "cooldown_ms", 0)
bus.Process(slotElement, slotResult, fakeRegion)
slots[2]["state"] := "EMPTY"
slots[2]["state_zh"] := "EMPTY"
slots[2]["occupied"] := false
bus.Process(slotElement, slotResult, fakeRegion)
if (slots[2]["state"] != "NOT_READY")
    ExitApp(1)
slots[2]["state"] := "EMPTY"
slots[2]["state_zh"] := "空位"
slots[2]["occupied"] := false
bus.Process(slotElement, slotResult, fakeRegion)
if (slots[2]["state"] != "NOT_READY")
    ExitApp(1)
slots[2]["state"] := "EMPTY"
slots[2]["state_zh"] := "空位"
slots[2]["occupied"] := false
bus.Process(slotElement, slotResult, fakeRegion)
if (slots[2]["state"] != "EMPTY" || slotResult["occupied_count"] != 2)
    ExitApp(1)

massSlots := []
Loop 12
    massSlots.Push(Map("index", A_Index, "state", "EMPTY", "state_zh", "空位", "occupied", false, "score", 0.95, "region", [0, 0, 10, 10]))
massResult := Map(
    "matched", false,
    "score", 0.0,
    "color", "",
    "latency_ms", 1,
    "error", "",
    "slots", massSlots,
    "slot_count", 12,
    "occupied_count", 0,
    "ready_count", 0,
    "master_count", 0,
    "summary_zh", ""
)
massElement := Map("id", "self_test_mass_slots", "lane", "medium", "method", "room_slots", "event_type", "ANY", "debounce_ms", 0, "cooldown_ms", 0)
bus.Process(massElement, massResult, fakeRegion)
Loop 5 {
    massSlots[A_Index]["state"] := "READY"
    massSlots[A_Index]["state_zh"] := "已准备"
    massSlots[A_Index]["occupied"] := true
}
bus.Process(massElement, massResult, fakeRegion)
guard := bus.slotSnapshotGuards["self_test_mass_slots"]
if (guard["count"] != 1 || guard["accepted"] || massResult["occupied_count"] != 0)
    ExitApp(1)
logger.Info("自检完成：配置、日志、事件模块可用。元素数量：" cfg.elements.Length)
ExitApp(0)
