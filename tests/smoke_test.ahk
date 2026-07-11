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

root := RegExReplace(A_ScriptDir, "\\tests$")
cfg := MonitorConfig.Load(root)
cfg.loggingEnabled := false
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
if (RoomStateDetector.HasMinimumMatches(1, 2) || !RoomStateDetector.HasMinimumMatches(2, 2))
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

selfBits := Buffer(310 * 57 * 4, 0)
selfCapture := Map("ok", true, "x", 0, "y", 0, "w", 310, "h", 57, "stride", 310 * 4, "bits", selfBits)
selectedRow := [0, 19, 310, 19]
singleEdgeRow := [0, 38, 310, 19]
DrawSelfBorder(selfCapture, selectedRow, true, true, 20, 180, 190)
DrawSelfBorder(selfCapture, singleEdgeRow, true, false, 20, 180, 190)
selectedMetrics := RoomStateDetector.ComputeSelfBorderMetrics(selfCapture, selectedRow)
singleEdgeMetrics := RoomStateDetector.ComputeSelfBorderMetrics(selfCapture, singleEdgeRow)
if !selectedMetrics["eligible"] || singleEdgeMetrics["eligible"]
    ExitApp(1)
dividerBits := Buffer(310 * 19 * 4, 0)
dividerCapture := Map("ok", true, "x", 0, "y", 0, "w", 310, "h", 19, "stride", 1240, "bits", dividerBits)
DrawSelfBorder(dividerCapture, [0, 0, 310, 19], true, true, 30, 110, 120)
dividerMetrics := RoomStateDetector.ComputeSelfBorderMetrics(dividerCapture, [0, 0, 310, 19])
if dividerMetrics["eligible"]
    ExitApp(1)
selfCandidateSlots := [
    MakeBorderCandidateSlot(1, true, 5.0, false),
    MakeBorderCandidateSlot(2, true, selectedMetrics["score"], true),
    MakeBorderCandidateSlot(3, true, singleEdgeMetrics["score"], false)
]
if (RoomStateDetector.SelectSelfCandidate(selfCandidateSlots) != 2)
    ExitApp(1)
selfCandidateSlots[1]["self_score"] := selectedMetrics["score"] - 5
selfCandidateSlots[1]["self_border_eligible"] := true
if (RoomStateDetector.SelectSelfCandidate(selfCandidateSlots) != 0)
    ExitApp(1)

cyanBackgroundBits := Buffer(310 * 19 * 4, 0)
cyanBackgroundCapture := Map("ok", true, "x", 0, "y", 0, "w", 310, "h", 19, "stride", 1240, "bits", cyanBackgroundBits)
FillTestRegion(cyanBackgroundCapture, Map("x", 0, "y", 0, "w", 310, "h", 19), 20, 180, 190)
cyanBackgroundMetrics := RoomStateDetector.ComputeSelfBorderMetrics(cyanBackgroundCapture, [0, 0, 310, 19])
if cyanBackgroundMetrics["eligible"]
    ExitApp(1)
whiteChannel := ScreenCapture.SelectSearchChannel(HexToRgb("0xFFFFFF"))
masterChannel := ScreenCapture.SelectSearchChannel(HexToRgb("0x66F603"))
if (whiteChannel["offset"] != 0 || masterChannel["offset"] != 2)
    ExitApp(1)

combatClient := Map("x", 0, "y", 0, "w", 1000, "h", 800)
combatRegions := CombatHudDetector.BuildRegions(combatClient)
combatBits := Buffer(1000 * 800 * 4, 0)
combatCapture := Map("ok", true, "error", "", "x", 0, "y", 0, "w", 1000, "h", 800, "stride", 4000, "bits", combatBits)
FillTestRegion(combatCapture, combatRegions["left"], 30, 60, 90)
FillTestFraction(combatCapture, combatRegions["left"], 0.10, 100, 220, 255)
FillTestRegion(combatCapture, combatRegions["score"], 30, 60, 90)
FillTestFraction(combatCapture, combatRegions["score"], 0.10, 100, 220, 255)
FillTestTail(combatCapture, combatRegions["score"], 0.05, 230, 80, 70)
FillTestRegion(combatCapture, combatRegions["radar"], 70, 210, 240)
FillTestTail(combatCapture, combatRegions["radar"], 0.10, 60, 180, 80)
FillTestRegion(combatCapture, combatRegions["hp"], 30, 60, 90)
FillTestFraction(combatCapture, combatRegions["hp"], 0.50, 100, 230, 255)
FillTestRegion(combatCapture, combatRegions["shield"], 30, 60, 90)
FillTestFraction(combatCapture, combatRegions["shield"], 1.00, 100, 230, 80)
FillTestRegion(combatCapture, combatRegions["ready"], 210, 170, 100)
DrawTestLine(combatCapture, combatRegions["ready"], 0.25, 0.20, 0.55, 240, 235, 225)
DrawTestLine(combatCapture, combatRegions["ready"], 0.65, 0.20, 0.55, 240, 235, 225)
combatResult := CombatHudDetector.Detect(Map(), combatClient, combatCapture)
if (!combatResult["matched"] || combatResult["anchor_hits"] != 3 || !combatResult["ready_raw"])
    ExitApp(1)
if (Abs(combatResult["hp_percent"] - 50) > 2 || combatResult["shield_percent"] < 98)
    ExitApp(1)
if (combatRegions["weapon_slots"].Length != 5 || !combatResult.Has("lock_state") || !combatResult.Has("target_presence"))
    ExitApp(1)

for _, slotRegion in combatRegions["weapon_slots"]
    FillTestRegion(combatCapture, slotRegion, 30, 35, 40)
FillTestRegion(combatCapture, combatRegions["weapon_slots"][2], 80, 220, 245)
selectedWeapon := CombatHudDetector.DetectSelectedWeapon(combatCapture, combatRegions["weapon_slots"])
if (selectedWeapon != 2)
    ExitApp(1)
weaponStates := CombatHudDetector.DetectWeaponSlots(combatCapture, combatRegions["weapon_slots"], selectedWeapon)
if (weaponStates[2]["state"] != "AVAILABLE" || weaponStates[1]["state"] != "UNAVAILABLE")
    ExitApp(1)

FillTestRegion(combatCapture, combatRegions["target"], 20, 30, 40)
targetRegion := combatRegions["target"]
arrowX := targetRegion["x"] + Round(targetRegion["w"] * 0.48)
arrowY := targetRegion["y"] + Round(targetRegion["h"] * 0.25)
FillTestRegion(combatCapture, Map("x", arrowX, "y", arrowY, "w", 60, "h", 3), 230, 40, 40)
FillTestRegion(combatCapture, Map("x", arrowX, "y", arrowY + 14, "w", 60, "h", 3), 230, 40, 40)
FillTestRegion(combatCapture, Map("x", arrowX + 50, "y", arrowY, "w", 3, "h", 80), 230, 40, 40)
directionOnly := CombatHudDetector.AnalyzeTargetMarkers(combatCapture, targetRegion)
if (directionOnly["presence"] != "ABSENT" || directionOnly["lock_state"] != "UNLOCKED")
    ExitApp(1)

FillTestRegion(combatCapture, targetRegion, 20, 30, 40)
markerWidth := Round(targetRegion["w"] * 0.08)
markerLeft := targetRegion["x"] + Round((targetRegion["w"] - markerWidth) / 2)
markerTop := targetRegion["y"] + Round(targetRegion["h"] * 0.45)
FillTestRegion(combatCapture, Map("x", markerLeft, "y", markerTop, "w", markerWidth, "h", 3), 230, 40, 40)
FillTestRegion(combatCapture, Map("x", markerLeft, "y", markerTop + 16, "w", markerWidth, "h", 3), 230, 40, 40)
FillTestRegion(combatCapture, Map("x", markerLeft + 10, "y", markerTop - 18, "w", 24, "h", 6), 230, 40, 40)
FillTestRegion(combatCapture, Map("x", markerLeft + 18, "y", markerTop + 24, "w", 8, "h", 8), 230, 40, 40)
FillTestRegion(combatCapture, Map("x", markerLeft + 34, "y", markerTop + 24, "w", 8, "h", 8), 230, 40, 40)
markerResult := CombatHudDetector.AnalyzeTargetMarkers(combatCapture, targetRegion)
if (markerResult["presence"] != "PRESENT" || markerResult["count"] < 1)
    ExitApp(1)

strongStats := Map("cyan", 0.20, "dark", 0.20, "red", 0.01, "green", 0.05)
weakStats := Map("cyan", 0.0, "dark", 0.0, "red", 0.0, "green", 0.0)
if (CombatHudDetector.CountAnchorHits(strongStats, strongStats, weakStats)["count"] != 2)
    ExitApp(1)
if (CombatHudDetector.CountAnchorHits(strongStats, weakStats, weakStats)["count"] != 1)
    ExitApp(1)

invalidBits := Buffer(100 * 10 * 4, 0)
invalidCapture := Map("ok", true, "x", 0, "y", 0, "w", 100, "h", 10, "stride", 400, "bits", invalidBits)
invalidRegion := Map("x", 0, "y", 0, "w", 100, "h", 10)
FillTestRegion(invalidCapture, invalidRegion, 200, 170, 100)
if (CombatHudDetector.MeasureGauge(invalidCapture, invalidRegion, "HP") != "")
    ExitApp(1)

combatTracker := CombatStateTracker(2, 250, 3, 500)
if combatTracker.Update(true, 0)["active"]
    ExitApp(1)
if !combatTracker.Update(true, 250)["active"]
    ExitApp(1)
if !combatTracker.Update(false, 500)["active"]
    ExitApp(1)
if !combatTracker.Update(false, 750)["active"]
    ExitApp(1)
combatExit := combatTracker.Update(false, 1000)
if (combatExit["active"] || !combatExit["changed"])
    ExitApp(1)

if Scheduler.SceneAllowed("ROOM", true, true) || !Scheduler.SceneAllowed("COMBAT", true, false)
    ExitApp(1)
combatPositionWide := OverlayManager.PlaceCombatOverlay(Map("x", 0, "y", 0, "w", 1920, "h", 1080), 200, 96)
combatPosition43 := OverlayManager.PlaceCombatOverlay(Map("x", 0, "y", 0, "w", 1024, "h", 768), 200, 96)
if (combatPositionWide["x"] != 1586 || combatPositionWide["y"] != 833)
    ExitApp(1)
if (combatPosition43["x"] != 752 || combatPosition43["y"] != 564)
    ExitApp(1)

overlayPosition := OverlayManager.PlaceOutsideRegion(scaledRegion, 620, 456, 2080, 1614)
if (overlayPosition["x"] != 664 || overlayPosition["y"] != 686)
    ExitApp(1)
logger := MonitorLogger(root, cfg)
logger.Info("自检开始：加载配置与模块。")
if (cfg.elements.Length < 1) {
    logger.Error("自检失败：elements.csv 没有可用元素。")
    ExitApp(1)
}
roomElement := ""
combatElement := ""
for _, element in cfg.elements {
    if (element["id"] = "room_slots") {
        roomElement := element
        break
    }
    if (element["id"] = "combat_hud")
        combatElement := element
}
if !IsObject(roomElement)
    ExitApp(1)
if (roomElement["region_h"] != 228 || roomElement["debounce_ms"] != 500 || roomElement["cooldown_ms"] != 600)
    ExitApp(1)
if !IsObject(combatElement) || combatElement["scene"] != "ANY" || roomElement["scene"] != "ROOM"
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

candidateState := Map("pending_count", 3, "pending_since", 100)
debouncedElement := Map("debounce_ms", 500)
if bus.IsSlotCandidateConfirmed(candidateState, debouncedElement, 599)
    ExitApp(1)
if !bus.IsSlotCandidateConfirmed(candidateState, debouncedElement, 600)
    ExitApp(1)

selfDebounceState := Map("pending_count", 3, "pending_since", 100)
if bus.IsSelfCandidateConfirmed(selfDebounceState, debouncedElement, 599)
    ExitApp(1)
if !bus.IsSelfCandidateConfirmed(selfDebounceState, debouncedElement, 600)
    ExitApp(1)

selfBus := MonitorEventBus(cfg, logger)
selfElement := Map("id", "self_test_identity", "lane", "medium", "method", "room_slots", "event_type", "ANY", "debounce_ms", 0, "cooldown_ms", 0)
selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 0)
    ExitApp(1)

selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 4)
    ExitApp(1)
selfBus.ResetRoomIdentity("自检房间重建")
selfResult := MakeSelfSlotResult(0)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 0)
    ExitApp(1)
selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 0)
    ExitApp(1)
selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 0)
    ExitApp(1)
selfResult := MakeSelfSlotResult(4)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 4 || !selfResult["slots"][4]["is_self"])
    ExitApp(1)

Loop 2 {
    selfResult := MakeSelfSlotResult(7)
    selfBus.Process(selfElement, selfResult, fakeRegion)
    if (selfResult["self_slot_index"] != 4)
        ExitApp(1)
}
selfResult := MakeSelfSlotResult(7)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 7 || !selfResult["slots"][7]["is_self"])
    ExitApp(1)

Loop 2 {
    selfResult := MakeSelfSlotResult(0)
    selfBus.Process(selfElement, selfResult, fakeRegion)
    if (selfResult["self_slot_index"] != 7)
        ExitApp(1)
}
selfResult := MakeSelfSlotResult(0)
selfBus.Process(selfElement, selfResult, fakeRegion)
if (selfResult["self_slot_index"] != 0)
    ExitApp(1)

formatSlot := Map("index", 1, "state_zh", "未准备", "is_self", false)
if (OverlayManager.FormatSlotLine(formatSlot) != "01号 未准备")
    ExitApp(1)
formatSlot["index"] := 12
formatSlot["is_self"] := true
if (OverlayManager.FormatSlotLine(formatSlot) != "12号 未准备 ★我")
    ExitApp(1)
selfJson := logger.ToJsonLine(Map(
    "is_self", true,
    "self_score", 123.5,
    "self_border_top", 0.75,
    "self_border_bottom", 0.80,
    "self_border_center", 0.10,
    "self_candidate_margin", 18.5,
    "self_slot_index", 12
))
if !InStr(selfJson, '"is_self":true') || !InStr(selfJson, '"self_border_top":0.750000') || !InStr(selfJson, '"self_candidate_margin":18.500000') || !InStr(selfJson, '"self_slot_index":12')
    ExitApp(1)
combatJson := logger.ToJsonLine(Map(
    "combat_active", true,
    "combat_phase", "READY",
    "hp_percent", 60,
    "shield_percent", 100,
    "anchor_hits", 3
))
if !InStr(combatJson, '"combat_active":true') || !InStr(combatJson, '"hp_percent":60') || !InStr(combatJson, '"anchor_hits":3')
    ExitApp(1)
detailJson := logger.ToJsonLine(Map(
    "selected_weapon_slot", 2,
    "weapon_slot_index", 3,
    "weapon_slot_state", "UNAVAILABLE",
    "lock_state", "LOCKED",
    "target_presence", "PRESENT"
))
if !InStr(detailJson, '"selected_weapon_slot":2') || !InStr(detailJson, '"weapon_slot_index":3') || !InStr(detailJson, '"lock_state":"LOCKED"')
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

MakeSelfSlotResult(candidateIndex) {
    slots := []
    Loop 12 {
        occupied := A_Index <= 8
        slots.Push(Map(
            "index", A_Index,
            "state", occupied ? "NOT_READY" : "EMPTY",
            "state_zh", occupied ? "未准备" : "空位",
            "occupied", occupied,
            "score", occupied ? 0.86 : 0.95,
            "self_score", A_Index = candidateIndex ? 120.0 : 20.0,
            "self_border_top", A_Index = candidateIndex ? 0.8 : 0.1,
            "self_border_bottom", A_Index = candidateIndex ? 0.8 : 0.1,
            "self_border_center", 0.1,
            "self_border_eligible", A_Index = candidateIndex,
            "is_self", false,
            "region", [0, (A_Index - 1) * 10, 10, 10]
        ))
    }
    return Map(
        "matched", true,
        "score", 8 / 12,
        "color", "",
        "latency_ms", 1,
        "error", "",
        "slots", slots,
        "self_candidate_index", candidateIndex,
        "self_candidate_margin", candidateIndex > 0 ? 100.0 : 0.0,
        "self_top_index", candidateIndex,
        "self_slot_index", 0,
        "slot_count", 12,
        "occupied_count", 8,
        "ready_count", 0,
        "master_count", 0,
        "summary_zh", ""
    )
}

MakeBorderCandidateSlot(index, occupied, score, eligible) {
    return Map(
        "index", index,
        "occupied", occupied,
        "self_score", score,
        "self_border_top", eligible ? 0.8 : 0.2,
        "self_border_bottom", eligible ? 0.8 : 0.2,
        "self_border_center", 0.1,
        "self_border_eligible", eligible
    )
}

DrawSelfBorder(capture, slotRegion, drawTop, drawBottom, red, green, blue) {
    x := slotRegion[1]
    y := slotRegion[2]
    w := slotRegion[3]
    h := slotRegion[4]
    edgeH := Max(2, Round(h * 0.11))
    bands := RoomStateDetector.BuildSelfBorderBands(x, w)
    for _, band in bands {
        if drawTop
            FillTestRegion(capture, Map("x", band["x"], "y", y, "w", band["w"], "h", edgeH), red, green, blue)
        if drawBottom
            FillTestRegion(capture, Map("x", band["x"], "y", y + h - edgeH, "w", band["w"], "h", edgeH), red, green, blue)
    }
}

FillTestRegion(capture, region, red, green, blue) {
    Loop region["h"] {
        y := region["y"] + A_Index - 1
        Loop region["w"] {
            x := region["x"] + A_Index - 1
            PutTestPixel(capture, x, y, red, green, blue)
        }
    }
}

FillTestFraction(capture, region, fraction, red, green, blue) {
    part := Map("x", region["x"], "y", region["y"], "w", Max(1, Round(region["w"] * fraction)), "h", region["h"])
    FillTestRegion(capture, part, red, green, blue)
}

FillTestTail(capture, region, fraction, red, green, blue) {
    width := Max(1, Round(region["w"] * fraction))
    part := Map("x", region["x"] + region["w"] - width, "y", region["y"], "w", width, "h", region["h"])
    FillTestRegion(capture, part, red, green, blue)
}

DrawTestLine(capture, region, yRatio, xRatio, widthRatio, red, green, blue) {
    y := region["y"] + Round((region["h"] - 1) * yRatio)
    startX := region["x"] + Round(region["w"] * xRatio)
    width := Round(region["w"] * widthRatio)
    Loop width
        PutTestPixel(capture, startX + A_Index - 1, y, red, green, blue)
}

PutTestPixel(capture, x, y, red, green, blue) {
    offset := (y - capture["y"]) * capture["stride"] + (x - capture["x"]) * 4
    NumPut("UChar", blue, capture["bits"], offset)
    NumPut("UChar", green, capture["bits"], offset + 1)
    NumPut("UChar", red, capture["bits"], offset + 2)
}
