#Requires AutoHotkey v2.0

class WindowManager {
    __New(config, logger) {
        this.config := config
        this.logger := logger
        this.hwnd := 0
        this.lastWarnTick := 0
    }

    FindTarget(logMissing := true) {
        exeName := this.config.targetExe
        title := this.config.targetTitle
        hwnd := exeName != "" ? WinExist("ahk_exe " exeName) : 0
        if (!hwnd && title != "")
            hwnd := WinExist(title)
        if (!hwnd && this.config.fallbackActiveWindow)
            hwnd := WinExist("A")

        if hwnd {
            this.hwnd := hwnd
            return hwnd
        }

        this.hwnd := 0
        if (logMissing && A_TickCount - this.lastWarnTick > 3000) {
            if (exeName != "" && ProcessExist(exeName))
                this.logger.Warn("检测到游戏进程但未找到可监测窗口：" exeName)
            else
                this.logger.Warn("未找到目标游戏窗口：" this.config.targetLabel)
            this.lastWarnTick := A_TickCount
        }
        return 0
    }

    GetTargetRect() {
        hwnd := this.hwnd ? this.hwnd : this.FindTarget(false)
        if !hwnd
            return Map("x", 0, "y", 0, "w", 0, "h", 0)
        try {
            WinGetPos(&x, &y, &w, &h, "ahk_id " hwnd)
            return Map("x", x, "y", y, "w", w, "h", h)
        } catch {
            return Map("x", 0, "y", 0, "w", 0, "h", 0)
        }
    }

    GetTargetClientRect() {
        hwnd := this.hwnd ? this.hwnd : this.FindTarget(false)
        if !hwnd
            return Map("x", 0, "y", 0, "w", 0, "h", 0)
        try {
            clientRect := Buffer(16, 0)
            if !DllCall("GetClientRect", "Ptr", hwnd, "Ptr", clientRect.Ptr)
                throw Error("GetClientRect failed")
            origin := Buffer(8, 0)
            if !DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", origin.Ptr)
                throw Error("ClientToScreen failed")
            return Map(
                "x", NumGet(origin, 0, "Int"),
                "y", NumGet(origin, 4, "Int"),
                "w", Max(1, NumGet(clientRect, 8, "Int")),
                "h", Max(1, NumGet(clientRect, 12, "Int"))
            )
        } catch {
            return this.GetTargetRect()
        }
    }

    RegionToScreen(element) {
        rect := this.GetTargetRect()
        return WindowManager.ScaleRegion(element, rect, this.config.referenceWidth, this.config.referenceHeight)
    }

    IsTargetForeground() {
        hwnd := this.hwnd ? this.hwnd : this.FindTarget(false)
        if !hwnd
            return false
        try {
            return WinActive("ahk_id " hwnd) = hwnd
        } catch {
            return false
        }
    }

    static ScaleRegion(element, rect, referenceWidth, referenceHeight) {
        scaleX := rect["w"] / Max(1, referenceWidth)
        scaleY := rect["h"] / Max(1, referenceHeight)
        return Map(
            "x", rect["x"] + Round(element["region_x"] * scaleX),
            "y", rect["y"] + Round(element["region_y"] * scaleY),
            "w", Max(1, Round(element["region_w"] * scaleX)),
            "h", Max(1, Round(element["region_h"] * scaleY))
        )
    }
}
