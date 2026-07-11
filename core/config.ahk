#Requires AutoHotkey v2.0

class MonitorConfig {
    static Load(root) {
        cfg := MonitorConfig()
        cfg.root := root
        cfg.configDir := JoinPath(root, "config")
        cfg.monitorIni := JoinPath(cfg.configDir, "monitor.ini")
        cfg.elementsCsv := JoinPath(cfg.configDir, "elements.csv")
        cfg.appName := "SDGO画面监测助手"

        cfg.developSettingsPath := IniRead(cfg.monitorIni, "develop", "settings_path", JoinPath(root, "..", "develop", "Data", "Settings.ini"))
        cfg.targetTitle := IniRead(cfg.monitorIni, "window", "target_title", "")
        cfg.targetExe := IniRead(cfg.monitorIni, "window", "target_exe", "")
        cfg.referenceWidth := Max(1, ToInt(IniRead(cfg.monitorIni, "window", "reference_width", "1040"), 1040))
        cfg.referenceHeight := Max(1, ToInt(IniRead(cfg.monitorIni, "window", "reference_height", "807"), 807))
        if (cfg.targetExe = "")
            cfg.targetExe := cfg.ReadDevelopGameExe("gonline.exe")
        cfg.targetLabel := cfg.targetExe != "" ? "游戏进程 " cfg.targetExe : "窗口标题 " cfg.targetTitle
        cfg.autoLaunchDemo := ToBool(IniRead(cfg.monitorIni, "window", "auto_launch_demo", "false"), false)
        cfg.fallbackActiveWindow := ToBool(IniRead(cfg.monitorIni, "window", "fallback_active_window", "false"), false)

        cfg.fastMs := Clamp(IniRead(cfg.monitorIni, "lanes", "fast_ms", "16"), 0, 50)
        cfg.mediumMs := Clamp(IniRead(cfg.monitorIni, "lanes", "medium_ms", "250"), 100, 900)
        cfg.slowMs := Clamp(IniRead(cfg.monitorIni, "lanes", "slow_ms", "3000"), 1000, 10000)
        cfg.fastMinSleepMs := Clamp(IniRead(cfg.monitorIni, "lanes", "fast_min_sleep_ms", "2"), 1, 20)
        cfg.fastCpuGuardMs := Clamp(IniRead(cfg.monitorIni, "lanes", "fast_cpu_guard_ms", "12"), 1, 50)

        cfg.overlayEnabled := ToBool(IniRead(cfg.monitorIni, "overlay", "enabled", "true"), true)
        cfg.overlayAlwaysOnTop := ToBool(IniRead(cfg.monitorIni, "overlay", "always_on_top", "true"), true)
        cfg.overlayClickThrough := ToBool(IniRead(cfg.monitorIni, "overlay", "click_through", "true"), true)
        cfg.overlayOpacity := Clamp(IniRead(cfg.monitorIni, "overlay", "opacity", "55"), 20, 100)

        cfg.loggingEnabled := ToBool(IniRead(cfg.monitorIni, "logging", "enabled", "true"), true)
        cfg.debugLogStable := ToBool(IniRead(cfg.monitorIni, "logging", "log_stable", "false"), false)
        cfg.elements := cfg.LoadElements()
        return cfg
    }

    ReadDevelopGameExe(defaultValue := "gonline.exe") {
        settingsPath := this.developSettingsPath
        if !FileExist(settingsPath)
            return defaultValue
        try {
            profile := IniRead(settingsPath, "Game", "ServerProfile", "")
            if (profile != "") {
                val := IniRead(settingsPath, "Server." profile, "GameExe", "")
                if (val != "")
                    return val
            }
            val := IniRead(settingsPath, "General", "GameExe", "")
            return val != "" ? val : defaultValue
        } catch {
            return defaultValue
        }
    }

    LoadElements() {
        elements := []
        if !FileExist(this.elementsCsv)
            return elements

        text := FileRead(this.elementsCsv, "UTF-8")
        lines := StrSplit(StrReplace(text, "`r", ""), "`n")
        headers := []

        for lineNo, line in lines {
            line := Trim(line)
            if (line = "" || SubStr(line, 1, 1) = "#")
                continue
            cols := CsvParseLine(line)
            if (headers.Length = 0) {
                headers := cols
                continue
            }
            row := Map()
            for idx, header in headers {
                value := idx <= cols.Length ? cols[idx] : ""
                row[header] := value
            }
            element := this.NormalizeElement(row, lineNo)
            if element["enabled"]
                elements.Push(element)
        }
        return elements
    }

    NormalizeElement(row, lineNo) {
        element := Map()
        element["line_no"] := lineNo
        element["id"] := this.GetRow(row, "id", "element_" lineNo)
        element["enabled"] := ToBool(this.GetRow(row, "enabled", "true"), true)
        element["lane"] := StrLower(this.GetRow(row, "lane", "fast"))
        element["method"] := StrLower(this.GetRow(row, "method", "color"))
        element["capture_type"] := StrLower(this.GetRow(row, "capture_type", "pixel"))
        element["region_x"] := ToInt(this.GetRow(row, "region_x", "0"), 0)
        element["region_y"] := ToInt(this.GetRow(row, "region_y", "0"), 0)
        element["region_w"] := Max(1, ToInt(this.GetRow(row, "region_w", "1"), 1))
        element["region_h"] := Max(1, ToInt(this.GetRow(row, "region_h", "1"), 1))
        element["template_path"] := this.GetRow(row, "template_path", "")
        element["color_hex"] := NormalizeHexColor(this.GetRow(row, "color_hex", "0x000000"))
        element["tolerance"] := Clamp(this.GetRow(row, "tolerance", "20"), 0, 255)
        element["threshold"] := Clamp(this.GetRow(row, "threshold", "0.90"), 0, 1)
        element["debounce_ms"] := Max(0, ToInt(this.GetRow(row, "debounce_ms", "0"), 0))
        element["cooldown_ms"] := Max(0, ToInt(this.GetRow(row, "cooldown_ms", "500"), 500))
        element["event_type"] := StrUpper(this.GetRow(row, "event_type", "ANY"))
        element["overlay"] := ToBool(this.GetRow(row, "overlay", "true"), true)
        element["scene"] := StrUpper(this.GetRow(row, "scene", "ANY"))

        if !(element["lane"] = "fast" || element["lane"] = "medium" || element["lane"] = "slow")
            element["lane"] := "fast"
        if !(element["scene"] = "ANY" || element["scene"] = "ROOM" || element["scene"] = "COMBAT")
            element["scene"] := "ANY"
        return element
    }

    GetRow(row, key, defaultValue := "") {
        return row.Has(key) ? row[key] : defaultValue
    }
}
