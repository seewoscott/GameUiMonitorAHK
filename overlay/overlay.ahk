#Requires AutoHotkey v2.0

class OverlayManager {
    __New(config, logger) {
        this.config := config
        this.logger := logger
        this.items := Map()
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
            w := 200
            h := 130
            position := OverlayManager.PlaceCombatOverlay(region, w, h)
        } else {
            w := result.Has("slots") ? Max(Round(region["w"] * 2 / 3), 100) : 300
            h := result.Has("slots") ? Max(region["h"], 184) : 128
            position := OverlayManager.PlaceOutsideRegion(region, w, h, A_ScreenWidth, A_ScreenHeight)
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
        text := "房间槽位 " titleStatus " " result["latency_ms"] "ms`n"
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

    static PlaceOutsideRegion(region, w, h, screenW, screenH, gap := 8) {
        rightX := region["x"] + region["w"] + gap
        if (rightX + w <= screenW)
            return Map("x", rightX, "y", Round(Clamp(region["y"], 0, Max(0, screenH - h))))

        leftX := region["x"] - gap - w
        if (leftX >= 0)
            return Map("x", leftX, "y", Round(Clamp(region["y"], 0, Max(0, screenH - h))))

        belowY := region["y"] + region["h"] + gap
        if (belowY + h <= screenH)
            return Map("x", Round(Clamp(region["x"], 0, Max(0, screenW - w))), "y", belowY)

        aboveY := region["y"] - gap - h
        return Map(
            "x", Round(Clamp(region["x"], 0, Max(0, screenW - w))),
            "y", Round(Clamp(aboveY, 0, Max(0, screenH - h)))
        )
    }

    static PlaceCombatOverlay(clientRect, w, h) {
        rightMargin := Round(clientRect["w"] * 0.07)
        bottomMargin := Round(clientRect["h"] * 0.14)
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
    }
}
