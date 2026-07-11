#Requires AutoHotkey v2.0

class MonitorEventBus {
    static RequiredSlotFrames := 3
    static RequiredSelfFrames := 3
    static RequiredSelfAmbiguousFrames := 3
    static MassChangeThreshold := 4
    static RequiredMassSnapshotFrames := 2

    __New(config, logger) {
        this.config := config
        this.logger := logger
        this.states := Map()
        this.selfSlotStates := Map()
        this.lastSelfCandidateLog := Map()
        this.slotSnapshotGuards := Map()
        this.lastSnapshotGuardLog := Map()
    }

    Process(element, result, region) {
        if result.Has("slots")
            return this.ProcessSlots(element, result, region)
        if (element["method"] = "combat_hud")
            return this.ProcessCombat(element, result, region)

        id := element["id"]
        now := A_TickCount
        if !this.states.Has(id) {
            this.states[id] := Map(
                "stable", result["matched"],
                "pending", "",
                "pending_since", 0,
                "last_emit", 0,
                "last_event", ""
            )
            if (element["method"] = "change" && result["matched"])
                return this.Emit(element, result, region, "ON_CHANGE", this.states[id], now)
            if (element["method"] != "change" && result["matched"])
                return this.Emit(element, result, region, "ON_APPEAR", this.states[id], now)
            return ""
        }
        state := this.states[id]
        method := element["method"]
        eventName := ""

        if (method = "change") {
            eventName := result["matched"] ? "ON_CHANGE" : "ON_STABLE"
        } else {
            if (result["matched"] != state["stable"]) {
                if (state["pending"] != result["matched"]) {
                    state["pending"] := result["matched"]
                    state["pending_since"] := now
                    return ""
                }
                if (now - state["pending_since"] < element["debounce_ms"])
                    return ""
                state["stable"] := result["matched"]
                state["pending"] := ""
                eventName := result["matched"] ? "ON_APPEAR" : "ON_DISAPPEAR"
            } else {
                state["pending"] := ""
                eventName := "ON_STABLE"
            }
        }

        if !this.ShouldEmit(element, eventName, state, now)
            return ""

        return this.Emit(element, result, region, eventName, state, now)
    }

    ProcessCombat(element, result, region) {
        id := element["id"]
        now := A_TickCount
        transition := result.Has("combat_transition") ? result["combat_transition"] : ""
        if !this.states.Has(id) {
            this.states[id] := Map(
                "stable", result["matched"],
                "pending", "",
                "pending_since", 0,
                "last_emit", 0,
                "last_event", ""
            )
        }
        state := this.states[id]
        state["stable"] := result["matched"]
        if (transition = "ENTER")
            return this.Emit(element, result, region, "ON_APPEAR", state, now)
        if (transition = "EXIT")
            return this.Emit(element, result, region, "ON_DISAPPEAR", state, now)
        return ""
    }

    ProcessSlots(element, result, region) {
        if this.ShouldSuppressSlotSnapshot(element, result) {
            this.ApplyStableSlotStates(element, result)
            this.ApplyStableSelfSlot(element, result)
            this.RefreshSlotSummary(result)
            return ""
        }

        this.ProcessSelfCandidate(element, result, A_TickCount)
        this.ApplyStableSelfSlot(element, result)
        summaryEvent := ""
        for _, slot in result["slots"] {
            slotEvent := this.ProcessSlot(element, result, region, slot)
            if (summaryEvent = "" && slotEvent != "")
                summaryEvent := slotEvent

        }
        this.ApplyStableSlotStates(element, result)
        this.ValidateStableSelfSlot(element, result)
        this.ApplyStableSelfSlot(element, result)
        this.RefreshSlotSummary(result)
        return summaryEvent
    }

    ProcessSelfCandidate(element, result, now) {
        id := element["id"]
        if !this.selfSlotStates.Has(id) {
            this.selfSlotStates[id] := Map(
                "stable_index", 0,
                "pending_index", 0,
                "pending_count", 0,
                "pending_since", 0,
                "ambiguous_count", 0
            )
        }

        state := this.selfSlotStates[id]
        candidate := result.Has("self_candidate_index") ? result["self_candidate_index"] : 0
        if (candidate > 0 && !this.IsRawSlotOccupied(result["slots"], candidate))
            candidate := 0

        if (candidate = 0) {
            this.LogAmbiguousSelfCandidate(id, result, now)
            state["pending_index"] := 0
            state["pending_count"] := 0
            state["pending_since"] := 0
            if (state["stable_index"] > 0) {
                state["ambiguous_count"] += 1
                if (state["ambiguous_count"] >= MonitorEventBus.RequiredSelfAmbiguousFrames)
                    this.ClearStableSelfSlot(id, state, "连续 3 帧无法区分高亮行")
            }
            return
        }

        state["ambiguous_count"] := 0
        if (candidate = state["stable_index"]) {
            state["pending_index"] := 0
            state["pending_count"] := 0
            state["pending_since"] := 0
            return
        }

        if (candidate != state["pending_index"]) {
            state["pending_index"] := candidate
            state["pending_count"] := 1
            state["pending_since"] := now
            return
        }

        state["pending_count"] += 1
        if !this.IsSelfCandidateConfirmed(state, element, now)
            return

        previousIndex := state["stable_index"]
        state["stable_index"] := candidate
        state["pending_index"] := 0
        state["pending_count"] := 0
        state["pending_since"] := 0
        if (previousIndex > 0)
            this.logger.Info("本人槽位换位确认：" Format("{:02}", previousIndex) "号 -> " Format("{:02}", candidate) "号。")
        else
            this.logger.Info("本人槽位确认：" Format("{:02}", candidate) "号。")
    }

    IsSelfCandidateConfirmed(state, element, now) {
        return (
            state["pending_count"] >= MonitorEventBus.RequiredSelfFrames
            && now - state["pending_since"] >= element["debounce_ms"]
        )
    }

    IsRawSlotOccupied(slots, slotIndex) {
        for _, slot in slots {
            if (slot["index"] = slotIndex)
                return slot["occupied"]
        }
        return false
    }

    ValidateStableSelfSlot(element, result) {
        id := element["id"]
        if !this.selfSlotStates.Has(id)
            return
        state := this.selfSlotStates[id]
        if (state["stable_index"] <= 0)
            return
        if !this.IsRawSlotOccupied(result["slots"], state["stable_index"])
            this.ClearStableSelfSlot(id, state, "原槽位已变为空位")
    }

    ClearStableSelfSlot(id, state, reason) {
        if (state["stable_index"] <= 0)
            return
        previousIndex := state["stable_index"]
        state["stable_index"] := 0
        state["pending_index"] := 0
        state["pending_count"] := 0
        state["pending_since"] := 0
        state["ambiguous_count"] := 0
        this.logger.Info("本人槽位变为待确认：原 " Format("{:02}", previousIndex) "号；" reason "。")
    }

    ApplyStableSelfSlot(element, result) {
        stableIndex := 0
        if this.selfSlotStates.Has(element["id"])
            stableIndex := this.selfSlotStates[element["id"]]["stable_index"]
        result["self_slot_index"] := stableIndex
        for _, slot in result["slots"]
            slot["is_self"] := stableIndex > 0 && slot["index"] = stableIndex
    }

    LogAmbiguousSelfCandidate(id, result, now) {
        if (!result.Has("occupied_count") || result["occupied_count"] <= 0)
            return
        if (this.lastSelfCandidateLog.Has(id) && now - this.lastSelfCandidateLog[id] < 5000)
            return
        topIndex := result.Has("self_top_index") ? result["self_top_index"] : 0
        if (topIndex <= 0)
            return
        topSlot := ""
        for _, slot in result["slots"] {
            if (slot["index"] = topIndex) {
                topSlot := slot
                break
            }
        }
        if !IsObject(topSlot)
            return
        margin := result.Has("self_candidate_margin") ? result["self_candidate_margin"] : 0.0
        this.logger.Info(
            "本人边框候选不明确：最高=" Format("{:02}", topIndex) "号；"
            "上=" Format("{:.2f}", topSlot["self_border_top"])
            "；下=" Format("{:.2f}", topSlot["self_border_bottom"])
            "；中=" Format("{:.2f}", topSlot["self_border_center"])
            "；分数=" Format("{:.1f}", topSlot["self_score"])
            "；领先=" Format("{:.1f}", margin) "。"
        )
        this.lastSelfCandidateLog[id] := now
    }

    ResetRoomIdentity(reason := "房间重新初始化") {
        for id, state in this.selfSlotStates {
            previousIndex := state["stable_index"]
            state["stable_index"] := 0
            state["pending_index"] := 0
            state["pending_count"] := 0
            state["pending_since"] := 0
            state["ambiguous_count"] := 0
            if (previousIndex > 0)
                this.logger.Info("本人槽位已重置：原 " Format("{:02}", previousIndex) "号；" reason "。")
        }
        this.lastSelfCandidateLog := Map()
    }

    ShouldSuppressSlotSnapshot(element, result) {
        id := element["id"]
        changedCount := 0
        for _, slot in result["slots"] {
            slotKey := id "#" slot["index"]
            if !this.states.Has(slotKey) {
                if this.slotSnapshotGuards.Has(id)
                    this.slotSnapshotGuards.Delete(id)
                return false
            }
            if (slot["state"] != this.states[slotKey]["stable_state"])
                changedCount += 1
        }

        if (changedCount < MonitorEventBus.MassChangeThreshold) {
            if this.slotSnapshotGuards.Has(id)
                this.slotSnapshotGuards.Delete(id)
            return false
        }

        snapshotKey := this.BuildSlotSnapshotKey(result["slots"])
        if !this.slotSnapshotGuards.Has(id) {
            this.slotSnapshotGuards[id] := Map("key", snapshotKey, "count", 1, "accepted", false)
        } else {
            guard := this.slotSnapshotGuards[id]
            if (guard["key"] = snapshotKey) {
                if guard["accepted"]
                    return false
                guard["count"] += 1
            } else {
                guard["key"] := snapshotKey
                guard["count"] := 1
                guard["accepted"] := false
            }
        }

        guard := this.slotSnapshotGuards[id]
        if (guard["count"] >= MonitorEventBus.RequiredMassSnapshotFrames) {
            guard["accepted"] := true
            return false
        }

        now := A_TickCount
        if (!this.lastSnapshotGuardLog.Has(id) || now - this.lastSnapshotGuardLog[id] >= 3000) {
            this.logger.Warn("抑制房间槽位异常整帧：同时变化 " changedCount " 个槽位。")
            this.lastSnapshotGuardLog[id] := now
        }
        return true
    }

    BuildSlotSnapshotKey(slots) {
        parts := []
        for _, slot in slots
            parts.Push(slot["state"])
        return JoinArray(parts, "|")
    }

    ApplyStableSlotStates(element, result) {
        for _, slot in result["slots"] {
            slotKey := element["id"] "#" slot["index"]
            if !this.states.Has(slotKey)
                continue
            stableState := this.states[slotKey]["stable_state"]
            slot["state"] := stableState
            slot["state_zh"] := RoomStateZh(stableState)
            slot["occupied"] := stableState != "EMPTY"
        }
    }

    ResetPending() {
        this.slotSnapshotGuards := Map()
        for _, state in this.states {
            if state.Has("pending")
                state["pending"] := ""
            if state.Has("pending_state")
                state["pending_state"] := ""
            if state.Has("pending_count")
                state["pending_count"] := 0
            if state.Has("pending_since")
                state["pending_since"] := 0
        }
        for _, state in this.selfSlotStates {
            state["pending_index"] := 0
            state["pending_count"] := 0
            state["pending_since"] := 0
            state["ambiguous_count"] := 0
        }
    }

    RefreshSlotSummary(result) {
        occupiedCount := 0
        readyCount := 0
        masterCount := 0
        for _, slot in result["slots"] {
            if slot["occupied"]
                occupiedCount += 1
            if (slot["state"] = "READY")
                readyCount += 1
            if (slot["state"] = "MASTER")
                masterCount += 1
        }
        result["occupied_count"] := occupiedCount
        result["ready_count"] := readyCount
        result["master_count"] := masterCount
        result["matched"] := occupiedCount > 0
        result["score"] := result["slot_count"] > 0 ? occupiedCount / result["slot_count"] : 0.0
        result["summary_zh"] := RoomStateDetector.BuildSummary(result["slots"])
    }

    ProcessSlot(element, result, region, slot) {
        slotKey := element["id"] "#" slot["index"]
        now := A_TickCount
        newState := slot["state"]

        if !this.states.Has(slotKey) {
            this.states[slotKey] := Map(
                "stable_state", newState,
                "pending_state", "",
                "pending_count", 0,
                "pending_since", 0,
                "last_emit", 0,
                "last_event", ""
            )
            if (newState != "EMPTY")
                return this.EmitSlot(element, result, slot, "ON_APPEAR", "", this.states[slotKey], now)
            return ""
        }

        state := this.states[slotKey]
        oldState := state["stable_state"]
        eventName := ""

        if (newState != oldState) {
            if (state["pending_state"] != newState) {
                state["pending_state"] := newState
                state["pending_count"] := 1
                state["pending_since"] := now
                return ""
            }
            state["pending_count"] += 1
            if !this.IsSlotCandidateConfirmed(state, element, now)
                return ""

            previousState := state["stable_state"]
            state["stable_state"] := newState
            state["pending_state"] := ""
            state["pending_count"] := 0
            if (previousState = "EMPTY" && newState != "EMPTY")
                eventName := "ON_APPEAR"
            else if (previousState != "EMPTY" && newState = "EMPTY")
                eventName := "ON_DISAPPEAR"
            else
                eventName := "ON_CHANGE"

            if !this.ShouldEmit(element, eventName, state, now)
                return ""
            return this.EmitSlot(element, result, slot, eventName, previousState, state, now)
        }

        state["pending_state"] := ""
        state["pending_count"] := 0
        eventName := "ON_STABLE"
        if !this.ShouldEmit(element, eventName, state, now)
            return ""
        return this.EmitSlot(element, result, slot, eventName, oldState, state, now)
    }

    IsSlotCandidateConfirmed(state, element, now) {
        return (
            state["pending_count"] >= MonitorEventBus.RequiredSlotFrames
            && now - state["pending_since"] >= element["debounce_ms"]
        )
    }

    EmitSlot(element, result, slot, eventName, previousState, state, now) {
        if !this.ShouldEmit(element, eventName, state, now)
            return ""

        state["last_emit"] := now
        state["last_event"] := eventName
        slotIndex := slot["index"]
        slotState := slot["state"]
        slotStateZh := RoomStateZh(slotState)
        previousStateZh := previousState != "" ? RoomStateZh(previousState) : ""
        message := this.BuildSlotMessage(slotIndex, eventName, previousStateZh, slotStateZh, result["latency_ms"])

        data := Map(
            "ts", NowStamp(),
            "id", element["id"],
            "lane", element["lane"],
            "method", element["method"],
            "event", eventName,
            "matched", slot["occupied"],
            "score", slot["score"],
            "is_self", slot.Has("is_self") ? slot["is_self"] : false,
            "self_score", slot.Has("self_score") ? slot["self_score"] : 0.0,
            "self_border_top", slot.Has("self_border_top") ? slot["self_border_top"] : 0.0,
            "self_border_bottom", slot.Has("self_border_bottom") ? slot["self_border_bottom"] : 0.0,
            "self_border_center", slot.Has("self_border_center") ? slot["self_border_center"] : 0.0,
            "self_candidate_margin", result.Has("self_candidate_margin") ? result["self_candidate_margin"] : 0.0,
            "self_slot_index", result.Has("self_slot_index") ? result["self_slot_index"] : 0,
            "region", slot["region"],
            "color", "",
            "latency_ms", result["latency_ms"],
            "error", result.Has("error") ? result["error"] : "",
            "slot_index", slotIndex,
            "state", slotState,
            "state_zh", slotStateZh,
            "previous_state", previousState,
            "previous_state_zh", previousStateZh,
            "room_summary_zh", result["summary_zh"],
            "message_zh", message
        )
        this.logger.Event(data)
        return eventName
    }

    BuildSlotMessage(slotIndex, eventName, previousStateZh, stateZh, latencyMs) {
        switch eventName {
            case "ON_APPEAR":
                return "房间槽位 " slotIndex " 出现，当前状态：" stateZh "，耗时 " latencyMs "ms"
            case "ON_DISAPPEAR":
                return "房间槽位 " slotIndex " 变为空位，上一状态：" previousStateZh "，耗时 " latencyMs "ms"
            case "ON_CHANGE":
                return "房间槽位 " slotIndex " 状态变化：" previousStateZh " → " stateZh "，耗时 " latencyMs "ms"
            case "ON_STABLE":
                return "房间槽位 " slotIndex " 状态稳定：" stateZh "，耗时 " latencyMs "ms"
            default:
                return "房间槽位 " slotIndex " 状态未知，耗时 " latencyMs "ms"
        }
    }

    Emit(element, result, region, eventName, state, now) {
        if !this.ShouldEmit(element, eventName, state, now)
            return ""
        id := element["id"]
        method := element["method"]
        state["last_emit"] := now
        state["last_event"] := eventName
        data := Map(
            "ts", NowStamp(),
            "id", id,
            "lane", element["lane"],
            "method", method,
            "event", eventName,
            "matched", result["matched"],
            "score", result["score"],
            "region", [region["x"], region["y"], region["w"], region["h"]],
            "color", result.Has("color") ? result["color"] : "",
            "latency_ms", result["latency_ms"],
            "error", result.Has("error") ? result["error"] : ""
        )
        if result.Has("combat_active") {
            data["combat_active"] := result["combat_active"]
            data["combat_phase"] := result["combat_phase"]
            data["hp_percent"] := result["hp_percent"]
            data["shield_percent"] := result["shield_percent"]
            data["anchor_hits"] := result["anchor_hits"]
            data["message_zh"] := eventName = "ON_APPEAR"
                ? "战斗 HUD 已确认，阶段：" result["combat_phase"] "，HP " this.PercentText(result["hp_percent"]) "，SHIELD " this.PercentText(result["shield_percent"]) "，耗时 " result["latency_ms"] "ms"
                : "战斗 HUD 已消失，返回房间场景确认流程，耗时 " result["latency_ms"] "ms"
        }
        this.logger.Event(data)
        return eventName
    }

    PercentText(value) {
        return value = "" ? "未知" : Round(value) "%"
    }

    ShouldEmit(element, eventName, state, now) {
        filter := element["event_type"]
        if !(filter = "" || filter = "ANY" || filter = "ALL" || filter = eventName)
            return false
        if (eventName = "ON_STABLE" && !this.config.debugLogStable && !(filter = "ON_STABLE"))
            return false
        cooldown := element["cooldown_ms"]
        if (cooldown > 0 && now - state["last_emit"] < cooldown && state["last_event"] = eventName)
            return false
        return true
    }
}
