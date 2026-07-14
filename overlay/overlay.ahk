#Requires AutoHotkey v2.0

class OverlayManager {
    __New(config, logger) {
        this.config := config
        this.logger := logger
        this.items := Map()
        this.selfDebugEnabled := false
        this.selfDebugRects := Map()
    }

    Update(element, result, region, eventName := "") {
        if (!this.config.overlayEnabled || !element["overlay"]) {
            this.Hide(element["id"])
            return
        }
        if (result.Has("combat_active") && !result["combat_active"]) {
            this.Hide(element["id"])
            return
        }

        id := element["id"]
        if !this.items.Has(id)
            this.items[id] := this.CreateItem(id)

        item := this.items[id]
        if result.Has("combat_active") {
            text := this.BuildCombatText(result)
        } else if result.Has("slots") {
            text := this.BuildSlotText(result, eventName)
        } else {
            label := this.OverlayLabel(id)
            status := eventName != "" ? EventZh(eventName) : (result["matched"] ? "命中" : "未命中")
            score := Format("{:.0f}%", result["score"] * 100)
            text := label "`n" status " " score "`n" result["latency_ms"] "ms"
        }
        item["text"].Text := text

        if result.Has("combat_active") {
            w := 350
            h := 350
            position := OverlayManager.PlaceCombatOverlay(region, w, h)
        } else {
            w := result.Has("slots") ? Max(Round(region["w"] * 2 / 3), 100) : 300
            h := result.Has("slots") ? Max(region["h"], 184) : 128
            position := OverlayManager.PlaceOutsideRegion(region, w, h, OverlayManager.GetPrimaryWorkArea())
        }
        item["text"].Move(4, 3, Max(130, w - 8), Max(44, h - 8))
        item["gui"].Show("x" position["x"] " y" position["y"] " w" w " h" h " NA")
        try WinSetTransparent(Round(255 * this.config.overlayOpacity / 100), "ahk_id " item["gui"].Hwnd)
    }

    OverlayLabel(id) {
        labels := Map(
            "start_button", "准备开始"
        )
        return labels.Has(id) ? labels[id] : id
    }

    BuildSlotText(result, eventName := "") {
        titleStatus := eventName != "" ? EventZh(eventName) : "稳定"
        debugFlag := this.selfDebugEnabled ? " [[调试中]]" : ""
        text := "房间槽位 " titleStatus " " result["latency_ms"] "ms" debugFlag "`n"
        text .= "有人 " result["occupied_count"] "，房主 " result["master_count"] "，已准备 " result["ready_count"] "`n"
        if (!result.Has("self_slot_index") || result["self_slot_index"] <= 0)
            text .= "本人：待确认`n"
        for _, slot in result["slots"]
            text .= OverlayManager.FormatSlotLine(slot) "`n"
        return RTrim(text, "`n")
    }

    static FormatSlotLine(slot) {
        marker := slot.Has("is_self") && slot["is_self"] ? " ★我" : ""
        return Format("{:02}", slot["index"]) "号 " slot["state_zh"] marker
    }

    BuildCombatText(result) {
        phase := result["combat_phase"] = "READY" ? "READY" : "进行中"
        hp := result["hp_percent"] = "" ? "--" : Round(result["hp_percent"]) "%"
        shield := result["shield_percent"] = "" ? "--" : Round(result["shield_percent"]) "%"
        anchors := ""
        anchors .= result["anchor_left"] ? "L" : "_"
        anchors .= result["anchor_score"] ? "S" : "_"
        anchors .= result["anchor_radar"] ? "R" : "_"
        if result.Has("selected_weapon_slot") {
            selected := result["selected_weapon_slot"] > 0 ? result["selected_weapon_slot"] : "?"
            slotParts := []
            if result.Has("weapon_slots") {
                for _, slot in result["weapon_slots"] {
                    marker := slot["state"] = "AVAILABLE" ? "A" : (slot["state"] = "UNAVAILABLE" ? "U" : "?")
                    slotParts.Push(slot["index"] ":" marker)
                }
            }
            lockText := result.Has("lock_state") && result["lock_state"] = "LOCKED" ? "是" : (result.Has("lock_state") && result["lock_state"] = "UNLOCKED" ? "否" : "?")
            targetText := result.Has("target_presence") && result["target_presence"] = "PRESENT" ? "有" : (result.Has("target_presence") && result["target_presence"] = "ABSENT" ? "无" : "?")
            return "战斗 " phase "`nHP " hp "`nSHIELD " shield
                . "`n武器 " selected "`n" JoinArray(slotParts, " ")
                . "`n锁定 " lockText "`n目标 " targetText
                . "`n" anchors " " result["latency_ms"] "ms"
        }
        return "战斗 " phase "`nHP " hp "`nSHIELD " shield "`n" anchors " " result["latency_ms"] "ms"
    }

    CreateItem(id) {
        opts := "-Caption +ToolWindow +Border -DPIScale"
        if this.config.overlayAlwaysOnTop
            opts .= " +AlwaysOnTop"
        if this.config.overlayClickThrough
            opts .= " +E0x20"
        g := Gui(opts, "Overlay " id)
        g.BackColor := "202020"
        g.MarginX := 4
        g.MarginY := 3
        g.SetFont("s9 cFFFFFF", "Microsoft YaHei UI")
        txt := g.Add("Text", "x4 y3 w210 h48 BackgroundTrans", "")
        return Map("gui", g, "text", txt)
    }

    static GetPrimaryWorkArea() {
        try {
            monitorNumber := MonitorGetPrimary()
            MonitorGetWorkArea(monitorNumber, &left, &top, &right, &bottom)
            return Map("left", left, "top", top, "right", right, "bottom", bottom)
        }
        return Map("left", 0, "top", 0, "right", A_ScreenWidth, "bottom", A_ScreenHeight)
    }

    static PlaceOutsideRegion(region, w, h, workArea, gap := 8) {
        leftEdge := workArea["left"]
        topEdge := workArea["top"]
        rightEdge := workArea["right"]
        bottomEdge := workArea["bottom"]
        rightX := region["x"] + region["w"] + gap
        if (rightX + w <= rightEdge)
            return Map("x", rightX, "y", Round(Clamp(region["y"], topEdge, Max(topEdge, bottomEdge - h))))

        leftX := region["x"] - gap - w
        if (leftX >= leftEdge)
            return Map("x", leftX, "y", Round(Clamp(region["y"], topEdge, Max(topEdge, bottomEdge - h))))

        belowY := region["y"] + region["h"] + gap
        if (belowY + h <= bottomEdge)
            return Map("x", Round(Clamp(region["x"], leftEdge, Max(leftEdge, rightEdge - w))), "y", belowY)

        aboveY := region["y"] - gap - h
        return Map(
            "x", Round(Clamp(region["x"], leftEdge, Max(leftEdge, rightEdge - w))),
            "y", Round(Clamp(aboveY, topEdge, Max(topEdge, bottomEdge - h)))
        )
    }

    static PlaceCombatOverlay(clientRect, w, h) {
        rightMargin := Round(clientRect["w"] * 0.07)
        bottomMargin := Round(clientRect["h"] * 0.08)
        x := clientRect["x"] + clientRect["w"] - w - rightMargin
        y := clientRect["y"] + clientRect["h"] - h - bottomMargin
        return Map(
            "x", Round(Clamp(x, clientRect["x"], clientRect["x"] + clientRect["w"] - w)),
            "y", Round(Clamp(y, clientRect["y"], clientRect["y"] + clientRect["h"] - h))
        )
    }

    Hide(id) {
        if this.items.Has(id) {
            try this.items[id]["gui"].Hide()
        }
    }

    HideAll() {
        for _, item in this.items {
            try item["gui"].Hide()
        }
        if this.HasOwnProp("testRect")
            try this.testRect.Hide()
        this.HideSelfBorderDebug()
    }

    ToggleSelfDebug() {
        this.selfDebugEnabled := !this.selfDebugEnabled
        this.logger.Info("自身槽位调试 " (this.selfDebugEnabled ? "开启" : "关闭"))
        if !this.selfDebugEnabled {
            if this.HasOwnProp("testRect")
                try this.testRect.Hide()
            return this.HideSelfBorderDebug()
        }

        ; 测试矩形：屏幕 (200,100) 200x50 不透明红色，确认 GUI 链路正常
        if !this.HasOwnProp("testRect")
            this.testRect := OverlayManager.CreateDebugRect()
        this.testRect.BackColor := "FF0000"
        this.testRect.Show("x200 y100 w200 h50 NA")
        WinSetTransparent(255, "ahk_id " this.testRect.Hwnd)
        this.logger.Info("调试测试矩形显示：x=200 y=100 w=200 h=50")
    }

    ShowSelfBorderDebug(slots) {
        if !this.selfDebugEnabled
            return
        if !IsObject(slots) || slots.Length = 0
            return

        maxIdx := 0
        for _, s in slots
            maxIdx := Max(maxIdx, s["index"])
        if maxIdx = 0
            return

        Loop maxIdx {
            if !this.selfDebugRects.Has(A_Index)
                this.selfDebugRects[A_Index] := OverlayManager.CreateDebugRect()
        }

        for _, slot in slots {
            idx := slot["index"]
            gui := this.selfDebugRects[idx]
            if !slot["occupied"] {
                try gui.Hide()
                continue
            }
            r := slot["region"]
            x := r[1], y := r[2], w := r[3], h := r[4]
            bandX := x + Max(1, Round(230 * w / 310))
            bandW := Max(1, Max(1, Round(244 * w / 310)) - Max(1, Round(230 * w / 310)))

            try gui.Show("x" bandX " y" y " w" bandW " h" h " NA")
            try WinSetTransparent(191, "ahk_id " gui.Hwnd)
        }
    }

    HideSelfBorderDebug() {
        for _, gui in this.selfDebugRects {
            try gui.Hide()
        }
    }

    static CreateDebugRect() {
        g := Gui("-Caption +ToolWindow +AlwaysOnTop -DPIScale")
        g.BackColor := "00FFFF"
        g.Hide()
        return g
    }
}
