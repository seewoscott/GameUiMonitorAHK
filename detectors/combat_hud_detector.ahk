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
            weaponsCapture := ScreenCapture.CaptureRegionPixels(regions["weapons"])
            viewCapture := ScreenCapture.CaptureRegionPixels(regions["view"])
            for name in ["left", "score", "radar", "hp", "shield"]
                captures[name] := topCapture
            captures["weapons"] := weaponsCapture
            captures["lock"] := viewCapture
            captures["target"] := viewCapture
            if !topCapture["ok"]
                errorMessage := "顶部 HUD 截图失败：" topCapture["error"]
        }

        if (errorMessage = "" && captures.Has("weapons") && !captures["weapons"]["ok"])
            errorMessage := "weapon HUD capture failed: " captures["weapons"]["error"]
        if (errorMessage = "" && captures.Has("lock") && !captures["lock"]["ok"])
            errorMessage := "combat view capture failed: " captures["lock"]["error"]

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
        ready := false
        hpPercent := matched ? CombatHudDetector.MeasureGauge(captures["hp"], regions["hp"], "HP") : ""
        shieldPercent := matched ? CombatHudDetector.MeasureGauge(captures["shield"], regions["shield"], "SHIELD") : ""
        selectedWeapon := matched ? CombatHudDetector.DetectSelectedWeapon(captures["weapons"], regions["weapon_slots"]) : 0
        weaponSlots := matched ? CombatHudDetector.DetectWeaponSlots(captures["weapons"], regions["weapon_slots"], selectedWeapon) : CombatHudDetector.UnknownWeaponSlots()
        markerAnalysis := matched
            ? CombatHudDetector.AnalyzeTargetMarkers(captures["target"], regions["target"])
            : Map("presence", "UNKNOWN", "lock_state", "UNKNOWN", "count", 0, "lock_score", 0.0)
        lockState := matched ? CombatHudDetector.DetectLockBrackets(captures["lock"], regions["lock"]) : "UNKNOWN"
        markerAnalysis["lock_score"] := lockState = "LOCKED" ? 1.0 : 0.0
        targetPresence := markerAnalysis["presence"]

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
            "anchor_radar", radarHit,
            "selected_weapon_slot", selectedWeapon,
            "weapon_slots", weaponSlots,
            "lock_state", lockState,
            "target_presence", targetPresence,
            "target_marker_count", markerAnalysis["count"],
            "lock_marker_score", markerAnalysis["lock_score"]
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
        weaponSlots := []
        for bounds in [
            [0.2750, 0.875, 0.3250, 0.995],
            [0.3800, 0.875, 0.4300, 0.995],
            [0.4800, 0.875, 0.5300, 0.995],
            [0.5750, 0.875, 0.6250, 0.995],
            [0.6800, 0.875, 0.7300, 0.995]
        ]
            weaponSlots.Push(CombatHudDetector.RelativeRegion(clientRect, bounds[1], bounds[2], bounds[3], bounds[4]))
        return Map(
            "left", CombatHudDetector.RelativeRegion(clientRect, 0.02, 0.02, 0.205, 0.125),
            "score", CombatHudDetector.RelativeRegion(clientRect, 0.40, 0.02, 0.59, 0.14),
            "radar", CombatHudDetector.RelativeRegion(clientRect, 0.80, 0.02, 0.995, 0.32),
            "hp", CombatHudDetector.RelativeRegion(clientRect, 0.068, 0.058, 0.184, 0.069),
            "shield", CombatHudDetector.RelativeRegion(clientRect, 0.068, 0.083, 0.184, 0.094),
            "weapons", CombatHudDetector.RelativeRegion(clientRect, 0.245, 0.865, 0.765, 1.0),
            "weapon_slots", weaponSlots,
            "view", CombatHudDetector.RelativeRegion(clientRect, 0.10, 0.20, 0.90, 0.80),
            "lock", CombatHudDetector.RelativeRegion(clientRect, 0.38, 0.30, 0.62, 0.72),
            "target", CombatHudDetector.RelativeRegion(clientRect, 0.10, 0.20, 0.90, 0.80)
        )
    }

    static RelativeRegion(rect, left, top, right, bottom) {
        x1 := rect["x"] + Round(rect["w"] * left)
        y1 := rect["y"] + Round(rect["h"] * top)
        x2 := rect["x"] + Round(rect["w"] * right)
        y2 := rect["y"] + Round(rect["h"] * bottom)
        return Map("x", x1, "y", y1, "w", Max(1, x2 - x1), "h", Max(1, y2 - y1))
    }

    static DetectSelectedWeapon(capture, slotRegions) {
        bestIndex := 0
        bestScore := 0.0
        secondScore := 0.0
        for index, region in slotRegions {
            stats := CombatHudDetector.MeasureRegionColors(capture, region, 3)
            score := stats["cyan"] * 3.0 + stats["bright"] * 0.25
            if (score > bestScore) {
                secondScore := bestScore
                bestScore := score
                bestIndex := index
            } else if (score > secondScore) {
                secondScore := score
            }
        }
        return bestScore >= 0.045 && bestScore - secondScore >= 0.008 ? bestIndex : 0
    }

    static DetectWeaponSlots(capture, slotRegions, selectedWeapon) {
        slots := []
        for index, region in slotRegions {
            stats := CombatHudDetector.MeasureRegionColors(capture, region, 3)
            state := "UNKNOWN"
            if (stats["red"] >= 0.035)
                state := "UNAVAILABLE"
            else if (index = selectedWeapon)
                state := "AVAILABLE"
            else if (stats["bright"] >= 0.008 || stats["cyan"] >= 0.008)
                state := "AVAILABLE"
            slots.Push(Map("index", index, "state", state, "score", Max(stats["bright"], stats["dark"])))
        }
        return slots
    }

    static UnknownWeaponSlots() {
        slots := []
        Loop 5
            slots.Push(Map("index", A_Index, "state", "UNKNOWN", "score", 0.0))
        return slots
    }

    static DetectLockState(capture, region) {
        return CombatHudDetector.DetectLockBrackets(capture, region)
    }

    static DetectLockBrackets(capture, region) {
        if !capture["ok"]
            return "UNKNOWN"
        x1 := Max(0, Round(region["x"] - capture["x"]))
        y1 := Max(0, Round(region["y"] - capture["y"]))
        x2 := Min(capture["w"] - 1, x1 + region["w"] - 1)
        y2 := Min(capture["h"] - 1, y1 + region["h"] - 1)
        if (x2 <= x1 || y2 <= y1)
            return "UNKNOWN"
        centerX := (x1 + x2) / 2
        leftCount := 0
        rightCount := 0
        leftMinY := y2
        leftMaxY := y1
        rightMinY := y2
        rightMaxY := y1
        step := 3
        y := y1
        while (y <= y2) {
            rowOffset := y * capture["stride"]
            x := x1
            while (x <= x2) {
                pixel := NumGet(capture["bits"], rowOffset + x * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if CombatHudDetector.IsLockGreen(r, g, b) {
                    if (x < centerX) {
                        leftCount += 1
                        leftMinY := Min(leftMinY, y)
                        leftMaxY := Max(leftMaxY, y)
                    } else {
                        rightCount += 1
                        rightMinY := Min(rightMinY, y)
                        rightMaxY := Max(rightMaxY, y)
                    }
                }
                x += step
            }
            y += step
        }
        minCount := Max(4, Round((region["w"] / step) * 0.025))
        minSpan := region["h"] * 0.10
        symmetric := leftCount >= minCount && rightCount >= minCount
        verticalShape := leftMaxY - leftMinY >= minSpan && rightMaxY - rightMinY >= minSpan
        return symmetric && verticalShape ? "LOCKED" : "UNLOCKED"
    }

    static DetectTargetPresence(capture, region) {
        return CombatHudDetector.AnalyzeTargetMarkers(capture, region)["presence"]
    }

    static AnalyzeTargetMarkers(capture, region) {
        if !capture["ok"]
            return Map("presence", "UNKNOWN", "lock_state", "UNKNOWN", "count", 0, "lock_score", 0.0)
        localX := Max(0, Round(region["x"] - capture["x"]))
        localY := Max(0, Round(region["y"] - capture["y"]))
        width := Min(region["w"], capture["w"] - localX)
        height := Min(region["h"], capture["h"] - localY)
        if (width <= 0 || height <= 0)
            return Map("presence", "UNKNOWN", "lock_state", "UNKNOWN", "count", 0, "lock_score", 0.0)

        step := 10
        minRunSamples := Max(5, Round(width * 0.018 / step))
        maxRunSamples := Max(minRunSamples + 1, Round(width * 0.16 / step))
        rowSegments := []
        y := 0
        while (y < height) {
            rowOffset := (localY + y) * capture["stride"] + localX * 4
            runStart := -1
            runHits := 0
            gap := 0
            x := 0
            while (x < width) {
                pixel := NumGet(capture["bits"], rowOffset + x * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if CombatHudDetector.IsEnemyMarkerRed(r, g, b) {
                    if (runStart < 0)
                        runStart := x
                    runHits += 1
                    gap := 0
                } else if (runStart >= 0) {
                    gap += 1
                    if (gap > 1) {
                        CombatHudDetector.AddMarkerSegment(rowSegments, y, runStart, x - gap * step, runHits, minRunSamples, maxRunSamples)
                        runStart := -1
                        runHits := 0
                        gap := 0
                    }
                }
                x += step
            }
            if (runStart >= 0)
                CombatHudDetector.AddMarkerSegment(rowSegments, y, runStart, width - 1, runHits, minRunSamples, maxRunSamples)
            y += 5
        }

        candidates := []
        maxPairGap := Max(8, Round(height * 0.045))
        minPairGap := Max(2, Round(height * 0.006))
        for firstIndex, first in rowSegments {
            secondIndex := firstIndex + 1
            pairChecks := 0
            while (secondIndex <= rowSegments.Length) {
                second := rowSegments[secondIndex]
                verticalGap := second["y"] - first["y"]
                if (verticalGap > maxPairGap)
                    break
                pairChecks += 1
                if (pairChecks > 40)
                    break
                if (
                    verticalGap >= minPairGap
                    && CombatHudDetector.SegmentOverlap(first, second) >= 0.55
                ) {
                    left := Max(first["x1"], second["x1"])
                    right := Min(first["x2"], second["x2"])
                    centerX := (left + right) / 2
                    supportWidth := Max(1, right - left)
                    above := CombatHudDetector.CountEnemyRed(
                        capture,
                        localX + Max(0, left - supportWidth * 0.35),
                        localY + Max(0, first["y"] - height * 0.065),
                        Min(width - 1, right + supportWidth * 0.35) - Max(0, left - supportWidth * 0.35),
                        Max(1, first["y"] - Max(0, first["y"] - height * 0.065)),
                        3
                    )
                    below := CombatHudDetector.CountEnemyRed(
                        capture,
                        localX + Max(0, left - supportWidth * 0.25),
                        localY + second["y"],
                        Min(width - 1, right + supportWidth * 0.25) - Max(0, left - supportWidth * 0.25),
                        Max(1, Min(height - second["y"], height * 0.075)),
                        3
                    )
                    minSupport := Max(2, Round(supportWidth / step * 0.05))
                    hasArrowStem := CombatHudDetector.HasLongRedStem(
                        capture,
                        localX + left,
                        localY + first["y"],
                        supportWidth,
                        Min(height - first["y"], Max(supportWidth * 1.6, height * 0.12))
                    )
                    supportConfirmed := (
                        (above >= minSupport && below >= minSupport)
                        || above + below >= minSupport * 3
                    )
                    if (!hasArrowStem && supportConfirmed) {
                        candidates.Push(Map(
                            "x", centerX,
                            "y", (first["y"] + second["y"]) / 2,
                            "width", supportWidth,
                            "support", above + below
                        ))
                        break
                    }
                }
                secondIndex += 1
            }
        }

        uniqueCandidates := CombatHudDetector.DeduplicateMarkerCandidates(candidates, width, height)
        lockScore := 0.0
        for _, candidate in uniqueCandidates {
            dx := Abs(candidate["x"] / width - 0.50)
            dy := Abs(candidate["y"] / height - 0.48)
            score := Max(0.0, 1.0 - dx / 0.075 - dy / 0.20)
            lockScore := Max(lockScore, score)
        }
        return Map(
            "presence", uniqueCandidates.Length > 0 ? "PRESENT" : "ABSENT",
            "lock_state", lockScore >= 0.40 ? "LOCKED" : "UNLOCKED",
            "count", uniqueCandidates.Length,
            "lock_score", lockScore
        )
    }

    static AddMarkerSegment(segments, y, x1, x2, hits, minHits, maxHits) {
        if (hits < minHits || hits > maxHits || x2 <= x1)
            return
        segments.Push(Map("y", y, "x1", x1, "x2", x2, "hits", hits))
    }

    static SegmentOverlap(first, second) {
        overlap := Min(first["x2"], second["x2"]) - Max(first["x1"], second["x1"])
        if (overlap <= 0)
            return 0.0
        shorter := Min(first["x2"] - first["x1"], second["x2"] - second["x1"])
        return shorter > 0 ? overlap / shorter : 0.0
    }

    static CountEnemyRed(capture, x, y, width, height, step := 3) {
        x1 := Max(0, Round(x))
        y1 := Max(0, Round(y))
        x2 := Min(capture["w"] - 1, x1 + Max(1, Round(width)) - 1)
        y2 := Min(capture["h"] - 1, y1 + Max(1, Round(height)) - 1)
        count := 0
        sampleY := y1
        while (sampleY <= y2) {
            rowOffset := sampleY * capture["stride"]
            sampleX := x1
            while (sampleX <= x2) {
                pixel := NumGet(capture["bits"], rowOffset + sampleX * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if CombatHudDetector.IsEnemyMarkerRed(r, g, b)
                    count += 1
                sampleX += step
            }
            sampleY += step
        }
        return count
    }

    static HasLongRedStem(capture, x, y, width, height) {
        sampleXs := [x + width * 0.12, x + width * 0.50, x + width * 0.88]
        requiredRun := Max(10, Round(width * 0.35))
        for _, sampleX in sampleXs {
            longest := 0
            current := 0
            sampleY := Max(0, Round(y))
            bottom := Min(capture["h"] - 1, sampleY + Round(height))
            while (sampleY <= bottom) {
                pixel := NumGet(capture["bits"], sampleY * capture["stride"] + Round(sampleX) * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                if CombatHudDetector.IsEnemyMarkerRed(r, g, b) {
                    current += 2
                    longest := Max(longest, current)
                } else {
                    current := 0
                }
                sampleY += 2
            }
            if (longest >= requiredRun)
                return true
        }
        return false
    }

    static DeduplicateMarkerCandidates(candidates, width, height) {
        unique := []
        for _, candidate in candidates {
            duplicate := false
            for _, existing in unique {
                if (
                    Abs(candidate["x"] - existing["x"]) <= width * 0.04
                    && Abs(candidate["y"] - existing["y"]) <= height * 0.06
                ) {
                    duplicate := true
                    break
                }
            }
            if !duplicate
                unique.Push(candidate)
        }
        return unique
    }

    static IsEnemyMarkerRed(r, g, b) {
        return r >= 200 && g <= 100 && b <= 100
    }

    static IsLockGreen(r, g, b) {
        return g >= 220 && r >= 180 && r <= 220 && b <= 180 && g - r >= 30 && g - b >= 50
    }

    static MeasureRegionColors(capture, region, step := 3) {
        empty := Map("cyan", 0.0, "red", 0.0, "bright", 0.0, "dark", 0.0)
        if !capture["ok"]
            return empty
        x1 := Max(0, Round(region["x"] - capture["x"]))
        y1 := Max(0, Round(region["y"] - capture["y"]))
        x2 := Min(capture["w"] - 1, x1 + region["w"] - 1)
        y2 := Min(capture["h"] - 1, y1 + region["h"] - 1)
        total := 0
        cyan := 0
        red := 0
        bright := 0
        dark := 0
        y := y1
        while (y <= y2) {
            rowOffset := y * capture["stride"]
            x := x1
            while (x <= x2) {
                pixel := NumGet(capture["bits"], rowOffset + x * 4, "UInt")
                b := pixel & 255
                g := (pixel >> 8) & 255
                r := (pixel >> 16) & 255
                total += 1
                if CombatHudDetector.IsHudCyan(r, g, b)
                    cyan += 1
                if (r >= 200 && r - g >= 100 && r - b >= 100)
                    red += 1
                if (Min(r, g, b) >= 165)
                    bright += 1
                if (Max(r, g, b) <= 95)
                    dark += 1
                x += step
            }
            y += step
        }
        if (total = 0)
            return empty
        return Map("cyan", cyan / total, "red", red / total, "bright", bright / total, "dark", dark / total)
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

    static IsHudCyan(r, g, b) {
        return g >= 170 && b >= 185 && b - r >= 35
    }

    static IsHpFill(r, g, b) {
        return g >= 180 && b >= 195 && b - r >= 30
    }

    static IsShieldFill(r, g, b) {
        return g >= 180 && g - r >= 30 && g - b >= 15
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
