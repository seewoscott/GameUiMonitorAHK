#Requires AutoHotkey v2.0

class RoomStateDetector {
    static SlotCount := 12
    static RequiredColorMatches := 1
    static SelfMinEdgeCoverage := 0.70
    static SelfMinMargin := 0.5

    static Detect(element, region) {
        start := A_TickCount
        slots := []
        slotCount := RoomStateDetector.SlotCount
        rowHeight := region["h"] / slotCount
        borderMargin := Max(2, Round(rowHeight * 0.16))
        captureRegion := Map(
            "x", region["x"],
            "y", region["y"] - borderMargin,
            "w", region["w"],
            "h", region["h"] + borderMargin * 2
        )
        capture := ScreenCapture.CaptureRegionPixels(captureRegion)

        Loop slotCount {
            slotIndex := A_Index
            bounds := RoomStateDetector.BuildSlotBounds(region, slotIndex, slotCount)
            slot := RoomStateDetector.DetectSlot(
                slotIndex,
                bounds["x"],
                bounds["y"],
                bounds["w"],
                bounds["h"],
                capture
            )
            slots.Push(slot)
        }

        for _, slot in slots {
            if slot["occupied"] {
                metrics := RoomStateDetector.ComputeSelfBorderMetrics(capture, slot["region"])
                slot["self_score"] := metrics["score"]
                slot["self_border_top"] := metrics["top"]
                slot["self_border_bottom"] := metrics["bottom"]
                slot["self_border_center"] := metrics["center"]
                slot["self_border_eligible"] := metrics["eligible"]
            }
        }
        selfCandidate := RoomStateDetector.SelectSelfCandidateDetails(slots)

        summary := RoomStateDetector.BuildSummary(slots)
        occupiedCount := 0
        readyCount := 0
        masterCount := 0
        for _, slot in slots {
            if slot["occupied"]
                occupiedCount += 1
            if (slot["state"] = "READY")
                readyCount += 1
            if (slot["state"] = "MASTER")
                masterCount += 1
        }

        return Map(
            "matched", occupiedCount > 0,
            "score", slotCount > 0 ? occupiedCount / slotCount : 0.0,
            "color", "",
            "latency_ms", A_TickCount - start,
            "error", capture["ok"] ? "" : "房间槽位截图失败：" capture["error"],
            "slots", slots,
            "self_candidate_index", selfCandidate["candidate_index"],
            "self_candidate_margin", selfCandidate["margin"],
            "self_top_index", selfCandidate["top_index"],
            "self_slot_index", 0,
            "slot_count", slotCount,
            "occupied_count", occupiedCount,
            "ready_count", readyCount,
            "master_count", masterCount,
            "summary_zh", summary
        )
    }

    static BuildSlotBounds(region, slotIndex, slotCount := 12) {
        slotCount := Max(1, slotCount)
        slotIndex := Round(Clamp(slotIndex, 1, slotCount))
        top := region["y"] + Round((slotIndex - 1) * region["h"] / slotCount)
        bottom := region["y"] + Round(slotIndex * region["h"] / slotCount)
        return Map(
            "x", region["x"],
            "y", top,
            "w", region["w"],
            "h", Max(1, bottom - top)
        )
    }

    static DetectSlot(slotIndex, x, y, w, h, capture) {
        regions := RoomStateDetector.BuildSlotRegions(x, y, w, h)
        nameRegion := regions["name"]
        statusRegion := regions["status"]

        hasMaster := RoomStateDetector.HasColor(capture, statusRegion, "0x66F603", 80)
        hasReady := !hasMaster && RoomStateDetector.HasColor(capture, statusRegion, "0x00FFFF", 70)
        hasName := !hasMaster && !hasReady && RoomStateDetector.HasColor(capture, nameRegion, "0xFFFFFF", 70)
        occupied := hasMaster || hasReady || hasName

        state := "EMPTY"
        confidence := 0.95
        if occupied {
            if hasMaster {
                state := "MASTER"
                confidence := 1.0
            } else if hasReady {
                state := "READY"
                confidence := 1.0
            } else {
                state := "NOT_READY"
                confidence := 0.86
            }
        }

        return Map(
            "index", slotIndex,
            "state", state,
            "state_zh", RoomStateZh(state),
            "previous_state", "",
            "occupied", occupied,
            "score", confidence,
            "is_self", false,
            "self_score", 0.0,
            "self_border_top", 0.0,
            "self_border_bottom", 0.0,
            "self_border_center", 0.0,
            "self_border_eligible", false,
            "region", [x, y, w, h]
        )
    }

    static ComputeSelfBorderMetrics(capture, slotRegion) {
        x := slotRegion[1]
        y := slotRegion[2]
        w := slotRegion[3]
        h := slotRegion[4]
        edgeH := Min(h, Max(2, Round(h * 0.11)))
        bands := RoomStateDetector.BuildSelfBorderBands(x, w)
        top := RoomStateDetector.MeasureBrightCyanEdge(capture, bands, y - edgeH, edgeH * 2)
        bottom := RoomStateDetector.MeasureBrightCyanEdge(capture, bands, y + h - edgeH, edgeH * 2)
        minEdge := Min(top, bottom)
        averageEdge := (top + bottom) / 2
        score := 100 * Clamp(0.65 * minEdge + 0.35 * averageEdge, 0, 1)
        eligible := minEdge >= RoomStateDetector.SelfMinEdgeCoverage
        return Map(
            "top", top,
            "bottom", bottom,
            "center", 0.0,
            "contrast", 0.0,
            "score", score,
            "eligible", eligible
        )
    }

    static BuildSelfBorderBands(x, w) {
        rightStart := x + RoomStateDetector.ScaleX(230, w)
        rightEnd := x + RoomStateDetector.ScaleX(244, w)
        return [
            Map("x", rightStart, "w", Max(1, rightEnd - rightStart))
        ]
    }

    static MeasureBrightCyanCoverage(capture, bands, y, height) {
        if !capture["ok"]
            return 0.0
        matched := 0
        total := 0
        for _, band in bands {
            localX := Round(band["x"] - capture["x"])
            localY := Round(y - capture["y"])
            if (localX < 0 || localY < 0 || localX + band["w"] > capture["w"] || localY + height > capture["h"])
                continue
            Loop height {
                rowOffset := (localY + A_Index - 1) * capture["stride"] + localX * 4
                Loop band["w"] {
                    pixel := NumGet(capture["bits"], rowOffset + (A_Index - 1) * 4, "UInt")
                    blue := pixel & 255
                    green := (pixel >> 8) & 255
                    red := (pixel >> 16) & 255
                    total += 1
                    if RoomStateDetector.IsBrightCyan(red, green, blue)
                        matched += 1
                }
            }
        }
        return total > 0 ? matched / total : 0.0
    }

    static MeasureBrightCyanEdge(capture, bands, y, height) {
        best := 0.0
        second := 0.0
        Loop height {
            coverage := RoomStateDetector.MeasureBrightCyanCoverage(capture, bands, y + A_Index - 1, 1)
            if (coverage > best) {
                second := best
                best := coverage
            } else if (coverage > second) {
                second := coverage
            }
        }
        return (best + second) / 2
    }

    static IsBrightCyan(red, green, blue) {
        return green >= 150 && blue >= 150 && Min(green, blue) - red >= 25
    }

    static SelectSelfCandidate(slots) {
        return RoomStateDetector.SelectSelfCandidateDetails(slots)["candidate_index"]
    }

    static SelectSelfCandidateDetails(slots) {
        topIndex := 0
        topScore := -1.0
        bestEligibleIndex := 0
        bestEligibleScore := -1.0
        secondEligibleScore := -1.0
        for _, slot in slots {
            if !slot["occupied"]
                continue
            score := slot.Has("self_score") ? slot["self_score"] : 0.0
            if (score > topScore) {
                topScore := score
                topIndex := slot["index"]
            }
            eligible := slot.Has("self_border_eligible") && slot["self_border_eligible"]
            if !eligible
                continue
            if (score > bestEligibleScore) {
                secondEligibleScore := bestEligibleScore
                bestEligibleScore := score
                bestEligibleIndex := slot["index"]
            } else if (score > secondEligibleScore) {
                secondEligibleScore := score
            }
        }
        margin := bestEligibleScore >= 0
            ? (secondEligibleScore >= 0 ? bestEligibleScore - secondEligibleScore : bestEligibleScore)
            : 0.0
        candidateIndex := bestEligibleIndex
        if (secondEligibleScore >= 0 && margin < RoomStateDetector.SelfMinMargin)
            candidateIndex := 0
        return Map(
            "candidate_index", candidateIndex,
            "top_index", topIndex,
            "top_score", Max(0.0, topScore),
            "margin", margin
        )
    }

    static BuildSlotRegions(x, y, w, h) {
        rowPadY := Max(1, Round(h / 19))
        contentH := Max(1, h - rowPadY * 2)
        nameX := x + RoomStateDetector.ScaleX(65, w)
        statusX := x + RoomStateDetector.ScaleX(245, w)
        statusRight := x + RoomStateDetector.ScaleX(305, w)
        nameRegion := Map("x", nameX, "y", y + rowPadY, "w", RoomStateDetector.ScaleX(165, w), "h", contentH)
        statusRegion := Map("x", statusX, "y", y + rowPadY, "w", Max(1, statusRight - statusX), "h", contentH)
        nameRegion := RoomStateDetector.CenterBand(nameRegion)
        statusRegion := RoomStateDetector.CenterBand(statusRegion)
        return Map("name", nameRegion, "status", statusRegion)
    }

    static ScaleX(referencePixels, actualWidth) {
        return Max(1, Round(referencePixels * actualWidth / 310))
    }

    static CenterBand(region) {
        bandH := Max(3, Round(region["h"] * 0.15))
        return Map(
            "x", region["x"],
            "y", region["y"] + Floor((region["h"] - bandH) / 2),
            "w", region["w"],
            "h", bandH
        )
    }

    static HasColor(capture, region, color, variation) {
        matchCount := ScreenCapture.CountColorMatches(
            capture,
            region,
            color,
            variation,
            RoomStateDetector.RequiredColorMatches
        )
        return RoomStateDetector.HasMinimumMatches(matchCount, RoomStateDetector.RequiredColorMatches)
    }

    static HasMinimumMatches(matchCount, minMatches) {
        return matchCount >= Max(1, minMatches)
    }

    static BuildSummary(slots) {
        parts := []
        for _, slot in slots
            parts.Push(slot["index"] "号" RoomStateZh(slot["state"]))
        return JoinArray(parts, "，")
    }
}
