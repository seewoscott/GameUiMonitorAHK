#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\core\combat_state.ahk
#Include ..\core\scheduler.ahk

config := TestConfig()
logger := TestLogger()
window := TestWindow()
overlay := TestOverlay()
eventBus := TestEventBus()
runner := TestScheduler(config, logger, window, overlay, eventBus)
runner.foregroundReady := true
anchor := config.elements[1]
roomSlots := config.elements[2]
combatHud := config.elements[3]

if Scheduler.SceneAllowed("ROOM", false, false)
    ExitApp(1)
if !Scheduler.SceneAllowed("ROOM", false, true)
    ExitApp(1)
if Scheduler.SceneAllowed("ROOM", true, true)
    ExitApp(1)

callsBeforeGate := runner.detectCalls
runner.RunElement(roomSlots)
if (runner.detectCalls != callsBeforeGate)
    ExitApp(1)

runner.QueueResult(AnchorResult(true))
runner.RunElement(anchor)
if runner.roomReady
    ExitApp(1)

runner.QueueResult(AnchorResult(false, "temporary capture failure"))
runner.RunElement(anchor)
if runner.roomReady
    ExitApp(1)

runner.QueueResult(AnchorResult(true))
runner.RunElement(anchor)
if !runner.roomReady
    ExitApp(1)

runner.QueueResult(RoomSlotsResult())
runner.RunElement(roomSlots)
if !runner.roomReady
    ExitApp(1)

runner.QueueResult(AnchorResult(false))
runner.RunElement(anchor)
if !runner.roomReady
    ExitApp(1)

runner.QueueResult(AnchorResult(false))
runner.RunElement(anchor)
if runner.roomReady
    ExitApp(1)

runner.QueueResult(AnchorResult(true))
runner.RunElement(anchor)
runner.QueueResult(AnchorResult(false))
runner.RunElement(anchor)
if runner.roomReady
    ExitApp(1)

runner.QueueResult(AnchorResult(true))
runner.RunElement(anchor)
runner.QueueResult(AnchorResult(true))
runner.RunElement(anchor)
if !runner.roomReady
    ExitApp(1)

runner.combatState := CombatStateTracker(2, 0, 3, 0)
runner.QueueResult(CombatResult(true))
runner.RunElement(combatHud)
if !runner.roomReady
    ExitApp(1)
runner.QueueResult(CombatResult(true))
runner.RunElement(combatHud)
if runner.roomReady
    ExitApp(1)

if (eventBus.identityResets < 3 || overlay.roomHideCount < 2)
    ExitApp(1)

ExitApp(0)

AnchorResult(matched, error := "") {
    return Map("matched", matched, "score", matched ? 1.0 : 0.0, "color", "", "latency_ms", 1, "error", error)
}

RoomSlotsResult() {
    return Map(
        "matched", false,
        "score", 0.0,
        "color", "",
        "latency_ms", 1,
        "error", "",
        "slots", [],
        "slot_count", 12,
        "occupied_count", 0,
        "ready_count", 0,
        "master_count", 0,
        "summary_zh", ""
    )
}

CombatResult(matched) {
    return Map(
        "matched", matched,
        "score", matched ? 1.0 : 0.0,
        "color", "",
        "latency_ms", 1,
        "error", "",
        "hp_percent", 100,
        "shield_percent", 100,
        "anchor_hits", matched ? 3 : 0
    )
}

class TestConfig {
    __New() {
        this.elements := [
            Map("id", "room_scene_anchor", "lane", "slow", "method", "image", "scene", "ROOM", "debounce_ms", 0),
            Map("id", "room_slots", "lane", "medium", "method", "room_slots", "scene", "ROOM", "debounce_ms", 0),
            Map("id", "combat_hud", "lane", "medium", "method", "combat_hud", "scene", "ANY", "debounce_ms", 0)
        ]
        this.fastMs := 16
        this.mediumMs := 250
        this.slowMs := 3000
        this.fastMinSleepMs := 2
        this.fastCpuGuardMs := 12
    }
}

class TestLogger {
    Info(message) {
    }

    Warn(message) {
    }

    Error(message) {
    }
}

class TestWindow {
    RegionToScreen(element) {
        return Map("x", 0, "y", 0, "w", 100, "h", 100)
    }

    GetTargetClientRect() {
        return Map("x", 0, "y", 0, "w", 100, "h", 100)
    }
}

class TestOverlay {
    __New() {
        this.roomHideCount := 0
    }

    Hide(id) {
        if (id = "room_slots")
            this.roomHideCount += 1
    }

    HideAll() {
    }

    Update(element, result, region, eventName := "") {
    }
}

class TestEventBus {
    __New() {
        this.identityResets := 0
    }

    Process(element, result, region) {
        return ""
    }

    ResetPending() {
    }

    ResetRoomIdentity(reason := "") {
        this.identityResets += 1
    }
}

class TestScheduler extends Scheduler {
    __New(config, logger, window, overlay, eventBus) {
        super.__New(config, logger, window, overlay, eventBus)
        this.results := []
        this.detectCalls := 0
    }

    QueueResult(result) {
        this.results.Push(result)
    }

    Detect(element, region) {
        this.detectCalls += 1
        if (this.results.Length = 0)
            throw Error("missing queued test result")
        return this.results.RemoveAt(1)
    }
}
