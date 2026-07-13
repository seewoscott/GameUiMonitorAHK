#Requires AutoHotkey v2.0
#SingleInstance Force

#Include core\utils.ahk
#Include core\config.ahk
#Include core\logger.ahk
#Include core\window.ahk
#Include capture\pixel_capture.ahk
#Include capture\screen_capture.ahk
#Include detectors\color_detector.ahk
#Include detectors\image_detector.ahk
#Include detectors\change_detector.ahk
#Include detectors\room_state_detector.ahk
#Include detectors\combat_hud_detector.ahk
#Include core\combat_state.ahk
#Include core\eventbus.ahk
#Include overlay\overlay.ahk
#Include core\scheduler.ahk

SetWorkingDir(A_ScriptDir)
CoordMode("Pixel", "Screen")
CoordMode("Mouse", "Screen")

for _, arg in A_Args {
    if (arg = "--check")
        ExitApp(0)
}

SetTimer(StartMonitorApp, -1)

StartMonitorApp(*) {
    global App
    try {
        App := MonitorApp()
        App.Start()
    } catch as err {
        EnsureDir(JoinPath(A_ScriptDir, "logs"))
        FileAppend(NowStamp() " [致命] 主程序启动失败：" err.Message "；文件：" err.File "；行：" err.Line "`n", JoinPath(A_ScriptDir, "logs", "fatal.log"), "UTF-8")
        MsgBox("主程序启动失败：" err.Message, "SDGO画面监测助手", "Iconx")
        ExitApp(1)
    }
}

class MonitorApp {
    static Version := "v2.0-dual-resolution"

    __New() {
        this.root := A_ScriptDir
        this.config := MonitorConfig.Load(this.root)
        this.sessionId := FormatTime(, "yyyyMMdd-HHmmss")
        this.logger := MonitorLogger(this.root, this.config, this.sessionId)
        this.window := WindowManager(this.config, this.logger)
        this.overlay := OverlayManager(this.config, this.logger)
        this.eventBus := MonitorEventBus(this.config, this.logger)
        this.scheduler := Scheduler(this.config, this.logger, this.window, this.overlay, this.eventBus)
        this.gui := ""
        this.statusText := ""
        this.laneText := ""
    }

    Start() {
        this.logger.Info(this.config.appName " 启动，项目目录：" this.root)
        this.logger.Info("会话：" this.sessionId "；代码版本：" MonitorApp.Version)
        this.logger.Info("当前版本：Monitor v2.0 纯 AHK，未启用 Python Worker。")
        this.logger.Info("目标：" this.config.targetLabel)
        this.logger.Info("Demo 测试窗口仅用于开发调试，启动时不会自动运行。")
        this.logger.Info("核心输出：房间大厅 " RoomStateDetector.SlotCount " 个可见玩家槽位状态。")
        this.logger.Info("战斗输出：场景、READY、HP 与 SHIELD；战斗优先隐藏房间 Overlay。")

        this.BuildStatusGui()
        Hotkey("^!F12", ObjBindMethod(this, "ReloadFromHotkey"))
        this.logger.Info("全局重载快捷键已注册：Ctrl+Alt+F12。")
        this.LogStartupGeometry()
        this.scheduler.Start()
        this.logger.Info("三档调度已启动：Fast=" this.config.fastMs "ms，Medium=" this.config.mediumMs "ms，Slow=" this.config.slowMs "ms。")
        this.RefreshStatus()
        SetTimer(ObjBindMethod(this, "RefreshStatus"), 1000)
    }

    BuildStatusGui() {
        this.gui := Gui("+AlwaysOnTop +Resize", this.config.appName)
        this.gui.SetFont("s10", "Microsoft YaHei UI")
        this.gui.Add("Text", "x16 y14 w430 h24", this.config.appName " " MonitorApp.Version)
        this.statusText := this.gui.Add("Text", "x16 y48 w560 h76", "状态：启动中")
        this.laneText := this.gui.Add("Text", "x16 y126 w560 h70", "")
        btnDemo := this.gui.Add("Button", "x16 y205 w120 h32", "启动测试窗口")
        btnDemo.OnEvent("Click", ObjBindMethod(this, "LaunchDemo"))
        btnLogs := this.gui.Add("Button", "x150 y205 w120 h32", "打开日志目录")
        btnLogs.OnEvent("Click", (*) => Run(JoinPath(this.root, "logs")))
        btnReload := this.gui.Add("Button", "x284 y205 w120 h32", "重载配置")
        btnReload.OnEvent("Click", ObjBindMethod(this, "Reload"))
        this.gui.OnEvent("Close", ObjBindMethod(this, "ExitApp"))
        this.gui.Show("w600 h255")
    }

    RefreshStatus(*) {
        hwnd := this.window.FindTarget(false)
        if hwnd {
            rect := this.window.GetTargetRect()
            monitorStatus := this.window.IsTargetForeground() ? "正在监测游戏窗口" : "已暂停（游戏不在前台）"
            this.statusText.Text := "状态：" monitorStatus "`n目标：" this.config.targetLabel "`n位置：x=" rect["x"] " y=" rect["y"] " w=" rect["w"] " h=" rect["h"]
        } else {
            this.statusText.Text := "状态：未找到游戏窗口`n目标：" this.config.targetLabel "`n请先通过 develop 项目启动游戏；测试窗口仅用于开发调试。"
        }
        stats := this.scheduler.GetStatsText()
        this.laneText.Text := stats
    }

    LaunchDemo(*) {
        demoPath := JoinPath(this.root, "tools", "demo_target.ahk")
        if FileExist(demoPath) {
            this.logger.Info("手动启动开发测试窗口。")
            Run('"' A_AhkPath '" "' demoPath '"')
        } else {
            this.logger.Error("未找到开发测试窗口脚本：" demoPath)
        }
    }

    Reload(*) {
        this.logger.Info("通过助手窗口重载，正在重启脚本。")
        Reload()
    }

    ReloadFromHotkey(*) {
        this.logger.Info("通过 Ctrl+Alt+F12 重载，正在重启脚本。")
        Reload()
    }

    LogStartupGeometry() {
        this.logger.Info("坐标基准：" this.config.referenceWidth "x" this.config.referenceHeight)
        displaySize := this.window.GetPrimaryPhysicalSize()
        this.logger.Info("主显示器物理分辨率：" displaySize["w"] "x" displaySize["h"])
        if !this.window.FindTarget(false) {
            this.logger.Info("启动时未找到游戏窗口，首次检测时再计算槽位区域。")
            return
        }

        rect := this.window.GetTargetRect()
        clientRect := this.window.GetTargetClientRect()
        this.logger.Info(
            "游戏客户端=[" clientRect["x"] "," clientRect["y"] "," clientRect["w"] "," clientRect["h"] "]"
        )
        for _, element in this.config.elements {
            if (element["id"] != "room_slots")
                continue
            region := this.window.RegionToScreen(element)
            this.logger.Info(
                "游戏窗口=[" rect["x"] "," rect["y"] "," rect["w"] "," rect["h"] "]；"
                "房间槽位区域=[" region["x"] "," region["y"] "," region["w"] "," region["h"] "]"
            )
            break
        }
    }

    ExitApp(*) {
        this.logger.Info("用户关闭 " this.config.appName "。")
        ExitApp()
    }
}
