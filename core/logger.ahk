#Requires AutoHotkey v2.0

class MonitorLogger {
    __New(root, config, sessionId := "") {
        this.root := root
        this.config := config
        if (sessionId = "")
            sessionId := FormatTime(, "yyyyMMdd-HHmmss")
        this.sessionId := sessionId
        this.logDir := JoinPath(root, "logs")
        EnsureDir(this.logDir)
        this.textLog := JoinPath(this.logDir, "monitor-" sessionId ".log")
        this.eventLog := JoinPath(this.logDir, "events-" sessionId ".jsonl")
        this.Cleanup(10)
    }

    Cleanup(maxFiles) {
        fileList := []
        Loop Files, this.logDir "\monitor-*.log"
            fileList.Push({path: A_LoopFileFullPath, time: FileGetTime(A_LoopFileFullPath, "M")})

        if (fileList.Length <= maxFiles)
            return

        Loop fileList.Length - maxFiles {
            oldestIdx := 1
            oldestTime := fileList[1].time
            Loop fileList.Length {
                idx := A_Index
                if (fileList[idx].time < oldestTime) {
                    oldestTime := fileList[idx].time
                    oldestIdx := idx
                }
            }
            logPath := fileList[oldestIdx].path
            jsonlPath := StrReplace(logPath, "monitor-", "events-")
            jsonlPath := StrReplace(jsonlPath, ".log", ".jsonl")
            SafeDeleteFile(logPath)
            SafeDeleteFile(jsonlPath)
            fileList.RemoveAt(oldestIdx)
        }
    }

    Info(message) {
        this.WriteText("信息", message)
    }

    Warn(message) {
        this.WriteText("警告", message)
    }

    Error(message) {
        this.WriteText("错误", message)
    }

    WriteText(level, message) {
        if !this.config.loggingEnabled
            return
        line := NowStamp() " [" level "] " message
        try FileAppend(line "`n", this.textLog, "UTF-8")
        catch
            OutputDebug("写入日志失败：" this.textLog)
        OutputDebug(line)
    }

    Event(eventData) {
        if !this.config.loggingEnabled
            return
        eventName := eventData.Has("event") ? eventData["event"] : "UNKNOWN"
        eventTextZh := eventData.Has("event_zh") ? eventData["event_zh"] : EventZh(eventName)
        id := eventData.Has("id") ? eventData["id"] : ""
        score := eventData.Has("score") ? eventData["score"] : 0
        latency := eventData.Has("latency_ms") ? eventData["latency_ms"] : 0
        message := eventData.Has("message_zh")
            ? eventData["message_zh"]
            : "画面识别项 " id " " eventTextZh "，匹配分数 " Format("{:.2f}", score) "，耗时 " latency "ms"

        eventData["event_zh"] := eventTextZh
        eventData["message_zh"] := message

        json := this.ToJsonLine(eventData)
        try FileAppend(json "`n", this.eventLog, "UTF-8")
        catch
            OutputDebug("写入事件日志失败：" this.eventLog)
        this.WriteText("事件", message)
    }

    ToJsonLine(data) {
        order := [
            "ts", "id", "lane", "method", "event", "event_zh", "message_zh",
            "matched", "score", "combat_active", "combat_phase", "hp_percent", "shield_percent", "anchor_hits",
            "selected_weapon_slot", "previous_weapon_slot", "weapon_slot_index", "weapon_slot_state",
            "previous_weapon_slot_state", "lock_state", "target_presence", "weapon_slots",
            "target_marker_count", "lock_marker_score",
            "slot_index", "is_self", "self_score", "self_border_top", "self_border_bottom",
            "self_border_center", "self_candidate_margin", "self_slot_index", "state", "state_zh",
            "previous_state", "previous_state_zh", "room_summary_zh",
            "region", "color", "latency_ms", "error"
        ]
        parts := []
        written := Map()
        for _, key in order {
            if data.Has(key) {
                parts.Push(JsonString(key) ":" this.JsonValue(data[key], key))
                written[key] := true
            }
        }
        for key, value in data {
            if !written.Has(key)
                parts.Push(JsonString(key) ":" this.JsonValue(value, key))
        }
        return "{" JoinArray(parts, ",") "}"
    }

    JsonValue(value, key := "") {
        if (key = "matched" || key = "occupied" || key = "is_self" || key = "combat_active")
            return value ? "true" : "false"
        if (
            key = "score"
            || key = "self_score"
            || key = "self_border_top"
            || key = "self_border_bottom"
            || key = "self_border_center"
            || key = "self_candidate_margin"
        )
            return Format("{:.6f}", value + 0)
        if (key = "hp_percent" || key = "shield_percent")
            return value = "" ? "null" : Round(value + 0) ""
        if (
            key = "latency_ms"
            || key = "slot_index"
            || key = "self_slot_index"
            || key = "anchor_hits"
            || key = "selected_weapon_slot"
            || key = "previous_weapon_slot"
            || key = "weapon_slot_index"
            || key = "target_marker_count"
        )
            return Round(value + 0) ""
        if (key = "region" && IsObject(value)) {
            items := []
            for _, item in value
                items.Push(Round(item + 0) "")
            return "[" JoinArray(items, ",") "]"
        }
        if IsObject(value) {
            if (Type(value) = "Array") {
                items := []
                for _, item in value
                    items.Push(this.JsonValue(item))
                return "[" JoinArray(items, ",") "]"
            }
            items := []
            for mapKey, item in value
                items.Push(JsonString(mapKey) ":" this.JsonValue(item, mapKey))
            return "{" JoinArray(items, ",") "}"
        }
        return JsonString(value)
    }
}

JoinArray(arr, sep := ",") {
    out := ""
    for idx, value in arr {
        if (idx > 1)
            out .= sep
        out .= value
    }
    return out
}
