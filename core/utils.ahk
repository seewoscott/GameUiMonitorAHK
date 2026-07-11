#Requires AutoHotkey v2.0

JoinPath(parts*) {
    path := ""
    for _, part in parts {
        part := StrReplace(part, "/", "\")
        if (part = "")
            continue
        if (path = "") {
            path := RTrim(part, "\")
        } else {
            path := RTrim(path, "\") "\" Trim(part, "\")
        }
    }
    return path
}

EnsureDir(path) {
    if !DirExist(path)
        DirCreate(path)
}

NowStamp() {
    return FormatTime(, "yyyy-MM-dd HH:mm:ss") "." Format("{:03}", A_MSec)
}

DateStamp() {
    return FormatTime(, "yyyyMMdd")
}

Clamp(value, minValue, maxValue) {
    value := ToFloat(value, minValue)
    if (value < minValue)
        return minValue
    if (value > maxValue)
        return maxValue
    return value
}

ToInt(value, defaultValue := 0) {
    try {
        if (value = "")
            return defaultValue
        return Round(value + 0)
    } catch {
        return defaultValue
    }
}

ToFloat(value, defaultValue := 0.0) {
    try {
        if (value = "")
            return defaultValue
        return value + 0.0
    } catch {
        return defaultValue
    }
}

ToBool(value, defaultValue := false) {
    value := StrLower(Trim(value))
    if (value = "")
        return defaultValue
    return value = "1" || value = "true" || value = "yes" || value = "on" || value = "是" || value = "开启"
}

NormalizeHexColor(value) {
    value := Trim(value)
    if (value = "")
        return "0x000000"
    value := StrReplace(value, "#", "")
    value := StrReplace(value, "0x", "")
    value := StrReplace(value, "0X", "")
    return "0x" Format("{:06X}", ("0x" value) + 0)
}

HexToRgb(value) {
    value := NormalizeHexColor(value)
    n := value + 0
    return Map("r", (n >> 16) & 255, "g", (n >> 8) & 255, "b", n & 255)
}

ColorDistance(c1, c2) {
    a := HexToRgb(c1)
    b := HexToRgb(c2)
    dr := Abs(a["r"] - b["r"])
    dg := Abs(a["g"] - b["g"])
    db := Abs(a["b"] - b["b"])
    return Max(dr, dg, db)
}

CsvParseLine(line) {
    result := []
    current := ""
    inQuotes := false
    i := 1
    while (i <= StrLen(line)) {
        ch := SubStr(line, i, 1)
        if (ch = '"') {
            nextCh := i < StrLen(line) ? SubStr(line, i + 1, 1) : ""
            if (inQuotes && nextCh = '"') {
                current .= '"'
                i += 2
                continue
            }
            inQuotes := !inQuotes
        } else if (ch = "," && !inQuotes) {
            result.Push(Trim(current))
            current := ""
        } else {
            current .= ch
        }
        i += 1
    }
    result.Push(Trim(current))
    return result
}

JsonEscape(value) {
    value := value ""
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`t", "\t")
    return value
}

JsonString(value) {
    return '"' JsonEscape(value) '"'
}

EventZh(eventName) {
    switch eventName {
        case "WEAPON_SELECTED_CHANGED":
            return "武器切换"
        case "WEAPON_SLOT_AVAILABLE":
            return "武器可用"
        case "WEAPON_SLOT_UNAVAILABLE":
            return "武器不可用"
        case "LOCK_ACQUIRED":
            return "锁定目标"
        case "LOCK_LOST":
            return "锁定丢失"
        case "TARGET_APPEARED":
            return "目标出现"
        case "TARGET_DISAPPEARED":
            return "目标消失"
        case "ON_APPEAR":
            return "出现"
        case "ON_DISAPPEAR":
            return "消失"
        case "ON_CHANGE":
            return "变化"
        case "ON_STABLE":
            return "稳定"
        default:
            return "未知"
    }
}

LaneZh(lane) {
    switch StrLower(lane) {
        case "fast":
            return "快速"
        case "medium":
            return "中速"
        case "slow":
            return "低速"
        default:
            return lane
    }
}

RoomStateZh(state) {
    switch StrUpper(state) {
        case "EMPTY":
            return "空位"
        case "OCCUPIED":
            return "有人"
        case "MASTER":
            return "房主"
        case "READY":
            return "已准备"
        case "NOT_READY":
            return "未准备"
        case "UNKNOWN":
            return "未知"
        default:
            return state
    }
}

ResolveProjectPath(root, path) {
    path := Trim(path)
    if (path = "")
        return ""
    if RegExMatch(path, "i)^[a-z]:\\")
        return path
    return JoinPath(root, path)
}

SafeDeleteFile(path) {
    if FileExist(path) {
        try FileDelete(path)
    }
}
