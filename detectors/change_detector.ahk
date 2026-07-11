#Requires AutoHotkey v2.0

class ChangeDetector {
    static Detect(element, region) {
        start := A_TickCount
        current := PixelCapture.AverageColor(region, 3)
        if !element.Has("_change_prev") {
            element["_change_prev"] := current
            return Map("matched", false, "score", 0.0, "color", current, "latency_ms", A_TickCount - start, "error", "")
        }

        previous := element["_change_prev"]
        distance := ColorDistance(current, previous)
        threshold := element["threshold"]
        score := Min(1.0, distance / 255.0)
        changed := score >= threshold
        if changed
            element["_change_prev"] := current

        return Map(
            "matched", changed,
            "score", score,
            "color", current,
            "latency_ms", A_TickCount - start,
            "error", ""
        )
    }
}
