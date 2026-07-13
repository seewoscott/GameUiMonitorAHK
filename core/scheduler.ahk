#Requires AutoHotkey v2.0

class Scheduler {
    __New(config, logger, window, overlay, eventBus) {
        this.config := config
        this.logger := logger
        this.window := window
        this.overlay := overlay
        this.eventBus := eventBus
        this.lanes := Map("fast", [], "medium", [], "slow", [])
        this.stats := Map()
        this.timers := Map()
        this.firstRunLogged := Map()
        this.lastSlowWarning := Map()
        this.foregroundState := ""
        this.foregroundWarmupCount := 0
        this.foregroundWarmupRequired := 3
        this.foregroundReady := false
        this.combatState := CombatStateTracker(2, 250, 3, 500)
        this.readyState := CombatStateTracker(2, 0, 2, 0)
        roomAnchorDebounceMs := 300
        for _, element in this.config.elements {
            if (element["id"] = "room_scene_anchor") {
                roomAnchorDebounceMs := element["debounce_ms"]
                break
            }
        }
        this.roomAnchorState := CombatStateTracker(2, roomAnchorDebounceMs, 2, roomAnchorDebounceMs)
        this.combatActive := false
        this.lastCombatResult := ""
        this.roomReady := false
        this.running := false

        for lane in ["fast", "medium", "slow"] {
            this.stats[lane] := Map("runs", 0, "last_elapsed", 0, "last_delay", 0, "last_start", 0, "errors", 0)
            this.timers[lane] := ObjBindMethod(this, "RunLane", lane)
        }

        for _, element in this.config.elements {
            lane := element["lane"]
            if this.lanes.Has(lane)
                this.lanes[lane].Push(element)
        }
    }

    Start() {
        this.running := true
        this.ScheduleLane("fast", 1)
        this.ScheduleLane("medium", 10)
        this.ScheduleLane("slow", 25)
    }

    Stop() {
        this.running := false
        for lane, timer in this.timers
            SetTimer(timer, 0)
        this.overlay.HideAll()
    }

    RunLane(lane) {
        if !this.running
            return

        start := A_TickCount
        if !this.window.FindTarget(lane != "fast") {
            this.UpdateForegroundState(false, "未找到游戏窗口")
            this.overlay.HideAll()
            this.ScheduleLane(lane, this.GetLanePeriod(lane))
            return
        }
        if !this.window.IsTargetForeground() {
            this.UpdateForegroundState(false, "游戏不在前台")
            this.overlay.HideAll()
            this.ScheduleLane(lane, this.GetLanePeriod(lane))
            return
        }
        this.UpdateForegroundState(true)

        for _, element in this.lanes[lane] {
            try {
                this.RunElement(element)
            } catch as err {
                this.stats[lane]["errors"] += 1
                this.logger.Error("检测元素 " element["id"] " 失败：" err.Message "；文件：" err.File "；行：" err.Line)
            }
        }

        elapsed := A_TickCount - start
        delay := this.ComputeNextDelay(lane, elapsed)
        this.stats[lane]["runs"] += 1
        this.stats[lane]["last_elapsed"] := elapsed
        this.stats[lane]["last_delay"] := delay
        this.stats[lane]["last_start"] := start
        this.ScheduleLane(lane, delay)
    }

    RunElement(element) {
        isCombatHud := element["method"] = "combat_hud"
        region := isCombatHud ? this.window.GetTargetClientRect() : this.window.RegionToScreen(element)
        if !this.foregroundReady {
            if !isCombatHud
                return
            result := this.Detect(element, region)
            if (result.Has("error") && result["error"] != "")
                return
            this.foregroundWarmupCount += 1
            this.overlay.HideAll()
            if (this.foregroundWarmupCount >= this.foregroundWarmupRequired) {
                this.foregroundReady := true
                this.eventBus.ResetPending()
                this.combatState.Reset(this.combatActive)
                this.readyState.Reset(false)
                this.logger.Info("游戏前台预热完成：连续 " this.foregroundWarmupRequired " 个有效 HUD 快照。")
            }
            return
        }

        if isCombatHud {
            this.RunCombatHud(element, region)
            return
        }

        if (element["id"] = "room_scene_anchor") {
            this.RunRoomSceneAnchor(element, region)
            return
        }

        scene := element.Has("scene") ? element["scene"] : "ANY"
        if !Scheduler.SceneAllowed(scene, this.combatActive, this.roomReady) {
            this.overlay.Hide(element["id"])
            return
        }

        result := this.Detect(element, region)
        this.LogRoomSlotMetrics(element, result, region)
        if (result.Has("error") && result["error"] != "") {
            this.logger.Warn("元素 " element["id"] " 检测警告：" result["error"])
            return
        }
        eventName := this.eventBus.Process(element, result, region)
        this.overlay.Update(element, result, region, eventName)
    }

    RunCombatHud(element, clientRect) {
        result := this.Detect(element, clientRect)
        this.LogCombatHudMetrics(element, result, clientRect)
        if (result.Has("error") && result["error"] != "") {
            this.logger.Warn("战斗 HUD 检测警告：" result["error"])
            return
        }

        rawActive := result["matched"]
        combatUpdate := this.combatState.Update(rawActive)
        this.combatActive := combatUpdate["active"]

        if rawActive {
            this.lastCombatResult := result
        } else if (this.combatActive && IsObject(this.lastCombatResult)) {
            result["hp_percent"] := this.lastCombatResult["hp_percent"]
            result["shield_percent"] := this.lastCombatResult["shield_percent"]
            result["anchor_hits"] := this.lastCombatResult["anchor_hits"]
        }

        result["matched"] := this.combatActive
        result["combat_active"] := this.combatActive
        result["combat_phase"] := "ACTIVE"
        result["combat_transition"] := combatUpdate["changed"]
            ? (this.combatActive ? "ENTER" : "EXIT")
            : ""

        if combatUpdate["changed"] {
            this.eventBus.ResetPending()
            this.roomAnchorState.Reset(false)
            if this.combatActive {
                this.SetRoomReady(false, "进入战斗场景")
                this.HideScene("ROOM")
                this.logger.Info("战斗场景已确认：隐藏并暂停房间检测。")
            } else {
                this.roomReady := false
                this.overlay.Hide(element["id"])
                this.lastCombatResult := ""
                this.logger.Info("战斗场景已结束：等待房间场景锚点连续 2 次匹配后恢复。")
            }
        }

        eventName := this.eventBus.Process(element, result, clientRect)
        if this.combatActive
            this.overlay.Update(element, result, clientRect, eventName)
        else
            this.overlay.Hide(element["id"])
    }

    RunRoomSceneAnchor(element, region) {
        if this.combatActive {
            this.overlay.Hide(element["id"])
            return
        }

        result := this.Detect(element, region)
        if (result.Has("error") && result["error"] != "") {
            this.logger.Warn("房间场景锚点检测警告：" result["error"])
            return
        }

        eventName := this.eventBus.Process(element, result, region)
        anchorUpdate := this.roomAnchorState.Update(result["matched"])
        if anchorUpdate["changed"]
            this.SetRoomReady(anchorUpdate["active"], anchorUpdate["active"] ? "场景锚点连续 2 次匹配" : "场景锚点连续 2 次未匹配")
        this.overlay.Update(element, result, region, eventName)
    }

    SetRoomReady(ready, reason) {
        ready := ready ? true : false
        if (this.roomReady = ready)
            return

        this.roomReady := ready
        this.eventBus.ResetPending()
        this.eventBus.ResetRoomIdentity(reason)
        if ready {
            this.logger.Info("房间场景已确认：" reason "。")
        } else {
            this.HideScene("ROOM")
            this.logger.Info("房间场景已失效：" reason "。")
        }
    }

    HideScene(scene) {
        for _, element in this.config.elements {
            elementScene := element.Has("scene") ? element["scene"] : "ANY"
            if (elementScene = scene)
                this.overlay.Hide(element["id"])
        }
    }

    static SceneAllowed(scene, combatActive, roomReady) {
        if (scene = "COMBAT")
            return combatActive
        if (scene = "ROOM")
            return !combatActive && roomReady
        return true
    }

    UpdateForegroundState(isForeground, reason := "") {
        if (this.foregroundState != "" && this.foregroundState = isForeground)
            return

        this.foregroundState := isForeground
        this.foregroundWarmupCount := 0
        this.foregroundReady := false
        this.eventBus.ResetPending()
        this.combatState.Reset(this.combatActive)
        this.roomAnchorState.Reset(this.roomReady)
        this.readyState.Reset(false)
        if isForeground {
            this.logger.Info("游戏返回前台，开始 " this.foregroundWarmupRequired " 帧槽位预热。")
        } else {
            this.overlay.HideAll()
            this.logger.Info("屏幕检测已暂停：" reason "；保留当前稳定槽位状态。")
        }
    }

    LogRoomSlotMetrics(element, result, region) {
        if (element["method"] != "room_slots")
            return

        id := element["id"]
        if !this.firstRunLogged.Has(id) {
            this.logger.Info(
                "房间槽位首轮检测：区域=[" region["x"] "," region["y"] "," region["w"] "," region["h"] "]；"
                "耗时=" result["latency_ms"] "ms"
            )
            this.firstRunLogged[id] := true
        }

        if (result["latency_ms"] <= 2000)
            return
        now := A_TickCount
        if (!this.lastSlowWarning.Has(id) || now - this.lastSlowWarning[id] >= 10000) {
            this.logger.Warn("房间槽位检测超时：" result["latency_ms"] "ms。")
            this.lastSlowWarning[id] := now
        }
    }

    LogCombatHudMetrics(element, result, clientRect) {
        id := element["id"]
        if !this.firstRunLogged.Has(id) {
            this.logger.Info(
                "战斗 HUD 首轮检测：客户端=[" clientRect["x"] "," clientRect["y"] "," clientRect["w"] "," clientRect["h"] "]；"
                "锚点=" result["anchor_hits"] "/3；耗时=" result["latency_ms"] "ms"
            )
            this.firstRunLogged[id] := true
        }
        if (result["latency_ms"] <= 500)
            return
        now := A_TickCount
        if (!this.lastSlowWarning.Has(id) || now - this.lastSlowWarning[id] >= 10000) {
            this.logger.Warn("战斗 HUD 检测超时：" result["latency_ms"] "ms。")
            this.lastSlowWarning[id] := now
        }
    }

    Detect(element, region) {
        method := element["method"]
        switch method {
            case "color":
                return ColorDetector.Detect(element, region)
            case "image":
                return ImageDetector.Detect(element, region, this.config.root)
            case "change":
                return ChangeDetector.Detect(element, region)
            case "room_slots":
                return RoomStateDetector.Detect(element, region)
            case "combat_hud":
                return CombatHudDetector.Detect(element, region)
            default:
                return Map("matched", false, "score", 0.0, "color", "", "latency_ms", 0, "error", "未知检测方法：" method)
        }
    }

    ComputeNextDelay(lane, elapsed) {
        period := this.GetLanePeriod(lane)
        if (lane = "fast") {
            if (period <= 0)
                return Max(this.config.fastMinSleepMs, elapsed > this.config.fastCpuGuardMs ? this.config.fastMinSleepMs + 2 : this.config.fastMinSleepMs)
            return Max(this.config.fastMinSleepMs, period - elapsed)
        }
        return Max(1, period - elapsed)
    }

    GetLanePeriod(lane) {
        switch lane {
            case "fast":
                return this.config.fastMs
            case "medium":
                return this.config.mediumMs
            case "slow":
                return this.config.slowMs
            default:
                return 1000
        }
    }

    ScheduleLane(lane, delay) {
        SetTimer(this.timers[lane], -Max(1, Round(delay)))
    }

    GetStatsText() {
        text := ""
        for lane in ["fast", "medium", "slow"] {
            stat := this.stats[lane]
            text .= LaneZh(lane) "：运行 " stat["runs"] " 次，最近耗时 " stat["last_elapsed"] "ms，下次延迟 " stat["last_delay"] "ms，错误 " stat["errors"] "`n"
        }
        return RTrim(text, "`n")
    }
}
