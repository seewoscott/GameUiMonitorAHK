#Requires AutoHotkey v2.0

class ScreenCapture {
    static CaptureRegion(region) {
        ; v1 先保留 AHK/GDI 截图接口占位。当前检测链路使用 PixelGetColor 与 ImageSearch。
        return Map("ok", true, "type", "region", "region", region)
    }

    static Capture() {
        return Map("ok", true, "type", "screen")
    }

    static CaptureRegionPixels(region) {
        width := Max(1, Round(region["w"]))
        height := Max(1, Round(region["h"]))
        screenDC := 0
        memoryDC := 0
        bitmap := 0
        previousObject := 0
        bits := Buffer(width * height * 4, 0)
        errorMessage := ""
        copied := false

        try {
            screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
            if !screenDC
                throw Error("GetDC failed")
            memoryDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
            if !memoryDC
                throw Error("CreateCompatibleDC failed")
            bitmap := DllCall("gdi32\CreateCompatibleBitmap", "Ptr", screenDC, "Int", width, "Int", height, "Ptr")
            if !bitmap
                throw Error("CreateCompatibleBitmap failed")
            previousObject := DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")

            rasterOperation := 0x40CC0020
            if !DllCall(
                "gdi32\BitBlt",
                "Ptr", memoryDC,
                "Int", 0,
                "Int", 0,
                "Int", width,
                "Int", height,
                "Ptr", screenDC,
                "Int", Round(region["x"]),
                "Int", Round(region["y"]),
                "UInt", rasterOperation,
                "Int"
            )
                throw Error("BitBlt failed")

            bitmapInfo := Buffer(40, 0)
            NumPut(
                "UInt", 40,
                "Int", width,
                "Int", -height,
                "UShort", 1,
                "UShort", 32,
                "UInt", 0,
                bitmapInfo
            )
            scanLines := DllCall(
                "gdi32\GetDIBits",
                "Ptr", memoryDC,
                "Ptr", bitmap,
                "UInt", 0,
                "UInt", height,
                "Ptr", bits.Ptr,
                "Ptr", bitmapInfo.Ptr,
                "UInt", 0,
                "Int"
            )
            if (scanLines != height)
                throw Error("GetDIBits returned " scanLines " of " height " scan lines")
            copied := true
        } catch as err {
            errorMessage := err.Message
        } finally {
            if (previousObject && memoryDC)
                DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", previousObject, "Ptr")
            if bitmap
                DllCall("gdi32\DeleteObject", "Ptr", bitmap)
            if memoryDC
                DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
            if screenDC
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
        }

        return Map(
            "ok", copied,
            "error", errorMessage,
            "x", Round(region["x"]),
            "y", Round(region["y"]),
            "w", width,
            "h", height,
            "stride", width * 4,
            "bits", bits
        )
    }

    static LoadImagePixels(path) {
        if !FileExist(path)
            return Map("ok", false, "error", "图片不存在：" path)

        bitmap := 0
        memoryDC := 0
        previousObject := 0
        screenDC := 0
        try {
            bitmap := LoadPicture(path, "GDI+")
            if !bitmap
                throw Error("LoadPicture failed")
            bitmapObject := Buffer(A_PtrSize = 8 ? 32 : 24, 0)
            if !DllCall("gdi32\GetObject", "Ptr", bitmap, "Int", bitmapObject.Size, "Ptr", bitmapObject.Ptr)
                throw Error("GetObject failed")
            width := NumGet(bitmapObject, 4, "Int")
            height := Abs(NumGet(bitmapObject, 8, "Int"))
            bits := Buffer(width * height * 4, 0)
            screenDC := DllCall("GetDC", "Ptr", 0, "Ptr")
            memoryDC := DllCall("gdi32\CreateCompatibleDC", "Ptr", screenDC, "Ptr")
            previousObject := DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", bitmap, "Ptr")
            bitmapInfo := Buffer(40, 0)
            NumPut(
                "UInt", 40,
                "Int", width,
                "Int", -height,
                "UShort", 1,
                "UShort", 32,
                "UInt", 0,
                bitmapInfo
            )
            scanLines := DllCall(
                "gdi32\GetDIBits",
                "Ptr", memoryDC,
                "Ptr", bitmap,
                "UInt", 0,
                "UInt", height,
                "Ptr", bits.Ptr,
                "Ptr", bitmapInfo.Ptr,
                "UInt", 0,
                "Int"
            )
            if (scanLines != height)
                throw Error("GetDIBits returned " scanLines " of " height " scan lines")
            return Map(
                "ok", true,
                "error", "",
                "x", 0,
                "y", 0,
                "w", width,
                "h", height,
                "stride", width * 4,
                "bits", bits
            )
        } catch as err {
            return Map("ok", false, "error", err.Message)
        } finally {
            if (previousObject && memoryDC)
                DllCall("gdi32\SelectObject", "Ptr", memoryDC, "Ptr", previousObject, "Ptr")
            if memoryDC
                DllCall("gdi32\DeleteDC", "Ptr", memoryDC)
            if screenDC
                DllCall("ReleaseDC", "Ptr", 0, "Ptr", screenDC)
            if bitmap
                DllCall("gdi32\DeleteObject", "Ptr", bitmap)
        }
    }

    static CountColorMatches(capture, region, color, variation, maxMatches := 1) {
        if !capture["ok"]
            return 0

        x1 := Max(0, Round(region["x"] - capture["x"]))
        y1 := Max(0, Round(region["y"] - capture["y"]))
        x2 := Min(capture["w"] - 1, Round(region["x"] + region["w"] - 1 - capture["x"]))
        y2 := Min(capture["h"] - 1, Round(region["y"] + region["h"] - 1 - capture["y"]))
        if (x2 < x1 || y2 < y1)
            return 0

        target := HexToRgb(color)
        variation := Round(Clamp(variation, 0, 255))
        maxMatches := Max(1, Round(maxMatches))
        channel := ScreenCapture.SelectSearchChannel(target)
        candidateBytes := ScreenCapture.BuildCandidateBytes(channel["value"], variation)
        count := 0
        for _, candidateByte in candidateBytes {
            y := y1
            while (y <= y2) {
                rowStart := capture["bits"].Ptr + y * capture["stride"] + x1 * 4
                rowEnd := capture["bits"].Ptr + y * capture["stride"] + (x2 + 1) * 4
                cursor := rowStart
                while (cursor < rowEnd) {
                    found := DllCall(
                        "msvcrt\memchr",
                        "Ptr", cursor,
                        "Int", candidateByte,
                        "UPtr", rowEnd - cursor,
                        "Ptr"
                    )
                    if !found
                        break

                    relativeOffset := found - rowStart
                    if (Mod(relativeOffset, 4) = channel["offset"]) {
                        pixelOffset := y * capture["stride"] + x1 * 4 + relativeOffset - channel["offset"]
                        blue := NumGet(capture["bits"], pixelOffset, "UChar")
                        green := NumGet(capture["bits"], pixelOffset + 1, "UChar")
                        red := NumGet(capture["bits"], pixelOffset + 2, "UChar")
                        if (
                            Abs(red - target["r"]) <= variation
                            && Abs(green - target["g"]) <= variation
                            && Abs(blue - target["b"]) <= variation
                        ) {
                            count += 1
                            if (count >= maxMatches)
                                return count
                        }
                    }
                    cursor := found + 1
                }
                y += 1
            }
        }
        return count
    }

    static GetPixelRgb(capture, x, y) {
        if !capture["ok"]
            return ""

        localX := Round(x - capture["x"])
        localY := Round(y - capture["y"])
        if (localX < 0 || localY < 0 || localX >= capture["w"] || localY >= capture["h"])
            return ""

        offset := localY * capture["stride"] + localX * 4
        return Map(
            "r", NumGet(capture["bits"], offset + 2, "UChar"),
            "g", NumGet(capture["bits"], offset + 1, "UChar"),
            "b", NumGet(capture["bits"], offset, "UChar")
        )
    }

    static GetPixelBgr(capture, x, y) {
        if !capture["ok"]
            return -1
        localX := Round(x - capture["x"])
        localY := Round(y - capture["y"])
        if (localX < 0 || localY < 0 || localX >= capture["w"] || localY >= capture["h"])
            return -1
        offset := localY * capture["stride"] + localX * 4
        return NumGet(capture["bits"], offset, "UInt") & 0xFFFFFF
    }

    static SelectSearchChannel(target) {
        channels := [
            Map("offset", 0, "value", target["b"]),
            Map("offset", 1, "value", target["g"]),
            Map("offset", 2, "value", target["r"])
        ]
        selected := channels[1]
        bestScore := -1
        for _, channel in channels {
            score := Min(channel["value"], 255 - channel["value"])
            if (score > bestScore) {
                selected := channel
                bestScore := score
            }
        }
        return selected
    }

    static BuildCandidateBytes(targetByte, variation) {
        values := []
        seen := Map()
        ScreenCapture.AddCandidateByte(values, seen, targetByte)
        delta := 16
        while (delta <= variation) {
            ScreenCapture.AddCandidateByte(values, seen, targetByte - delta)
            ScreenCapture.AddCandidateByte(values, seen, targetByte + delta)
            delta += 16
        }
        if (variation > 0) {
            ScreenCapture.AddCandidateByte(values, seen, targetByte - variation)
            ScreenCapture.AddCandidateByte(values, seen, targetByte + variation)
        }
        return values
    }

    static AddCandidateByte(values, seen, value) {
        value := Round(Clamp(value, 0, 255))
        if seen.Has(value)
            return
        seen[value] := true
        values.Push(value)
    }
}

capture_region(region) {
    return ScreenCapture.CaptureRegion(region)
}

capture() {
    return ScreenCapture.Capture()
}
