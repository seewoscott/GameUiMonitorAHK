#Requires AutoHotkey v2.0

class ColorDetector {
    static Detect(element, region) {
        start := A_TickCount
        expected := element["color_hex"]
        tolerance := element["tolerance"]
        samples := element["capture_type"] = "region"
            ? PixelCapture.SampleRegion(region, 3)
            : [Map("x", region["x"] + Floor(region["w"] / 2), "y", region["y"] + Floor(region["h"] / 2), "color", PixelCapture.GetPixel(region["x"] + Floor(region["w"] / 2), region["y"] + Floor(region["h"] / 2)))]

        bestScore := 0.0
        bestColor := ""
        matched := false
        for _, sample in samples {
            color := sample["color"]
            if (color = "")
                continue
            distance := ColorDistance(color, expected)
            score := 1.0 - Min(1.0, distance / 255.0)
            if (score > bestScore) {
                bestScore := score
                bestColor := color
            }
            if (distance <= tolerance)
                matched := true
        }

        return Map(
            "matched", matched,
            "score", bestScore,
            "color", bestColor,
            "latency_ms", A_TickCount - start,
            "error", ""
        )
    }
}
