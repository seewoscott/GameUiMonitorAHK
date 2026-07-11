#Requires AutoHotkey v2.0

class CombatHudDetector {
    static RequiredAnchorHits := 2

    static Detect(element, clientRect, sourceCapture := "") {
        start := A_TickCount
        regions := CombatHudDetector.BuildRegions(clientRect)
        captures := Map()
        errorMessage := ""
        if IsObject(sourceCapture) {
            for name, _ in regions
                captures[name] := sourceCapture
        } else {
            topRegion := CombatHudDetector.UnionRegions([
                regions["left"],
                regions["score"],
                regions["radar"]
            ])
            topCapture := ScreenCapture.CaptureRegionPixels(topRegion)
            readyCapture := ScreenCapture.CaptureRegionPixels(regions["ready"])
            for name in ["left", "score", "radar", "hp", "shield"]
                captures[name] := topCapture
            captures["ready"] := readyCapture
            if !topCapture["ok"]
                errorMessage := "顶部 HUD 截图失败：" topCapture["error"]
            else if !readyCapture["ok"]
                errorMessage := "READY 截图失败：" readyCapture["error"]
        }

        result := CombatHudDetector.Analyze(regions, captures)
        result["latency_ms"] := A_TickCount - start
        result["error"] := errorMessage
        return result
    }

    static Analyze(regions, captures) {
        leftStats := CombatHudDetector.MeasureHudColors(captures["left"], regions["left"])
        scoreStats := CombatHudDetector.MeasureHudColors(captures["score"], regions["score"])
        radarStats := CombatHudDetector.MeasureHudColors(captures["radar"], regions["radar"])
        anchorResult := CombatHudDetector.CountAnchorHits(leftStats, scoreStats, radarStats)
        leftHit := anchorResult["left"]
        scoreHit := anchorResult["score"]
        radarHit := anchorResult["radar"]
        anchorHits := anchorResult["count"]
        matched := anchorHits >= CombatHudDetector.RequiredAnchorHits
        ready := matched && CombatHudDetector.DetectReady(captures["ready"], regions["ready"])
        hpPercent := matched ? CombatHudDetector.MeasureGauge(captures["hp"], regions["hp"], "HP") : ""
        shieldPercent := matched ? CombatHudDetector.MeasureGauge(captures["shield"], regions["shield"], "SHIELD") : ""

        return Map(
            "matched", matched,
            "score", anchorHits / 3,
            "color", "",
            "latency_ms", 0,
            "error", "",
            "combat_active", matched,
            "combat_phase", ready ? "READY" : "ACTIVE",
            "ready_raw", ready,
            "hp_percent", hpPercent,
            "shield_percent", shieldPercent,
            "anchor_hits", anchorHits,
            "anchor_left", leftHit,
            "anchor_score", scoreHit,
            "anchor_radar", radarHit
        )
    }

    static CountAnchorHits(leftStats, scoreStats, radarStats) {
        leftHit := leftStats["cyan"] >= 0.015 && leftStats["dark"] >= 0.15
        scoreHit := scoreStats["cyan"] >= 0.015 && scoreStats["red"] >= 0.002 && scoreStats["dark"] >= 0.15
        radarHit := radarStats["cyan"] >= 0.015 && radarStats["green"] >= 0.002 && radarStats["dark"] >= 0.15
        return Map(
            "left", leftHit,
            "score", scoreHit,
            "radar", radarHit,
            "count", (leftHit ? 1 : 0) + (scoreHit ? 1 : 0) + (radarHit ? 1 : 0)
        )
    }

    static BuildRegions(clientRect) {
        return Map(
            "left", CombatHudDetector.RelativeRegion(clientRect, 0.02, 0.02, 0.205, 0.125),
            "score", CombatHudDetector.RelativeRegion(clientRect, 0.40, 0.02, 0.59, 0.14),
            "radar", CombatHudDetector.RelativeRegion(clientRect, 0.80, 0.02, 0.995, 0.32),
            "ready", CombatHudDetector.RelativeRegion(clientRect, 0.54, 0.84, 0.68, 0.96),
            "hp", CombatHudDetector.RelativeRegion(clientRect, 0.068, 0.058, 0.184, 0.069),
            "shield", CombatHudDetector.RelativeRegion(clientRect, 0.068, 0.083, 0.184, 0.094)
        )
    }

    static RelativeRegion(rect, left, top, right, bottom) {
        x1 := rect["x"] + Round(rect["w"] * left)
        y1 := rect["y"] + Round(rect["h"] * top)
        x2 := rect["x"] + Round(rect["w"] * right)
        y2 := rect["y"] + Round(rect["h"] * bottom)
        return Map("x", x1, "y", y1, "w", Max(1, x2 - x1), "h", Max(1, y2 - y1))
    }

    static UnionRegions(regions) {
        left := regions[1]["x"]
        top := regions[1]["y"]
        right := left + regions[1]["w"]
        bottom := top + regions[1]["h"]
        for _, region in regions {
            left := Min(left, region["x"])
            top := Min(top, region["y"])
            right := Max(right, region["x"] + region["w"])
            bottom := Max(bottom, region["y"] + region["h"])
        }
        return Map("x", left, "y", top, "w", right - left, "h", bottom - top)
    }

    static MeasureHudColors(capture, region) {
        if !capture["ok"]
            return Map("cyan", 0.0, "dark", 0.0, "red", 0.0, "green", 0.0)
        step := Max(1, Round(Min(region["w"], region["h"]) / 60))
        x1 := Max(0, Round(region["x"] - capture["x"]))
        y1 := Max(0, Round(region["y"] - capture["y"]))
        x2 := Min(capture["w"] - 1, x1 + region["w"] - 1)
        y2 := Min(capture["h"] - 1, y1 + region["h"] - 1)
        total := 0
        cyan := 0
        dark := 0
        red := 0
        green := 0
        y := y1
        while (y <= y2) {
            x := x1
            rowOffset := y * capture["stride"]
            while (x <= x2) {
                pixel := NumGet(capture["bits"], rowOffset + x * 4, "UInt")
                total += 1
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if CombatHudDetector.IsHudCyan(r, g, b)
                    cyan += 1
                if (r < 80 && g < 120 && b < 155)
                    dark += 1
                if (r >= 180 && r - g >= 35)
                    red += 1
                if (g >= 130 && g - r >= 20 && g - b >= 5)
                    green += 1
                x += step
            }
            y += step
        }
        if (total = 0)
            return Map("cyan", 0.0, "dark", 0.0, "red", 0.0, "green", 0.0)
        return Map(
            "cyan", cyan / total,
            "dark", dark / total,
            "red", red / total,
            "green", green / total
        )
    }

    static MeasureGauge(capture, region, gaugeType) {
        if !capture["ok"]
            return ""
        lineValues := []
        for ratio in [0.25, 0.50, 0.75] {
            y := region["y"] + Round((region["h"] - 1) * ratio)
            value := CombatHudDetector.MeasureGaugeLine(capture, region, y, gaugeType)
            if (value != "")
                lineValues.Push(value)
        }
        if (lineValues.Length < 2)
            return ""
        return Round(CombatHudDetector.Median(lineValues))
    }

    static MeasureGaugeLine(capture, region, y, gaugeType) {
        width := region["w"]
        localX := Round(region["x"] - capture["x"])
        localY := Round(y - capture["y"])
        if (localX < 0 || localY < 0 || localX + width > capture["w"] || localY >= capture["h"])
            return ""
        rowOffset := localY * capture["stride"] + localX * 4
        firstHit := -1
        lastHit := -1
        gap := 0
        maxGap := Max(2, Round(width * 0.02))
        darkCount := 0
        Loop width {
            offset := A_Index - 1
            pixel := NumGet(capture["bits"], rowOffset + offset * 4, "UInt")
            b := pixel & 255
            g := (pixel >> 8) & 255
            r := (pixel >> 16) & 255
            filled := gaugeType = "HP"
                ? CombatHudDetector.IsHpFill(r, g, b)
                : CombatHudDetector.IsShieldFill(r, g, b)
            if filled {
                if (firstHit < 0)
                    firstHit := offset
                lastHit := offset
                gap := 0
            } else if (firstHit >= 0) {
                gap += 1
                if (gap > maxGap)
                    break
            }
            if (r < 95 && g < 125 && b < 165)
                darkCount += 1
        }

        if (firstHit < 0)
            return darkCount / width >= 0.35 ? 0 : ""
        if (firstHit > width * 0.12)
            return ""
        return Clamp((lastHit + 1) * 100 / width, 0, 100)
    }

    static DetectReady(capture, region) {
        if !capture["ok"]
            return false
        localX := Round(region["x"] - capture["x"])
        localY := Round(region["y"] - capture["y"])
        if (localX < 0 || localY < 0 || localX + region["w"] > capture["w"] || localY + region["h"] > capture["h"])
            return false
        qualifyingRows := []
        sampleStep := 2
        sampleWidth := Ceil(region["w"] / sampleStep)
        minRun := Round(sampleWidth * 0.35)
        Loop region["h"] {
            y := localY + A_Index - 1
            rowOffset := y * capture["stride"] + localX * 4
            longest := 0
            current := 0
            Loop sampleWidth {
                pixel := NumGet(capture["bits"], rowOffset + (A_Index - 1) * sampleStep * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if CombatHudDetector.IsReadyWhite(r, g, b) {
                    current += 1
                    longest := Max(longest, current)
                } else {
                    current := 0
                }
            }
            if (longest >= minRun)
                qualifyingRows.Push(region["y"] + y - localY)
        }
        if (qualifyingRows.Length < 2)
            return false
        return qualifyingRows[qualifyingRows.Length] - qualifyingRows[1] >= region["h"] * 0.15
    }

    static IsHudCyan(r, g, b) {
        return g >= 170 && b >= 185 && b - r >= 35
    }

    static IsHpFill(r, g, b) {
        return g >= 180 && b >= 195 && b - r >= 30
    }

    static IsShieldFill(r, g, b) {
        return g >= 180 && g - r >= 30 && g - b >= 15
    }

    static IsReadyWhite(r, g, b) {
        return Min(r, g, b) >= 190 && Max(r, g, b) - Min(r, g, b) <= 65
    }

    static Median(values) {
        sorted := []
        for _, value in values
            sorted.Push(value)
        Loop sorted.Length {
            i := A_Index
            j := i + 1
            while (j <= sorted.Length) {
                if (sorted[j] < sorted[i]) {
                    tmp := sorted[i]
                    sorted[i] := sorted[j]
                    sorted[j] := tmp
                }
                j += 1
            }
        }
        middle := Floor((sorted.Length + 1) / 2)
        if Mod(sorted.Length, 2)
            return sorted[middle]
        return (sorted[middle] + sorted[middle + 1]) / 2
    }
}
