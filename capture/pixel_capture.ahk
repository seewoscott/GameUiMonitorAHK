#Requires AutoHotkey v2.0

class PixelCapture {
    static GetPixel(x, y) {
        try {
            return PixelGetColor(x, y, "RGB")
        } catch as err {
            return ""
        }
    }

    static SampleRegion(region, grid := 3) {
        samples := []
        grid := Max(1, grid)
        stepX := region["w"] <= 1 ? 1 : Max(1, Floor(region["w"] / grid))
        stepY := region["h"] <= 1 ? 1 : Max(1, Floor(region["h"] / grid))
        y := region["y"] + Floor(stepY / 2)
        while (y < region["y"] + region["h"]) {
            x := region["x"] + Floor(stepX / 2)
            while (x < region["x"] + region["w"]) {
                color := PixelCapture.GetPixel(x, y)
                if (color != "")
                    samples.Push(Map("x", x, "y", y, "color", color))
                x += stepX
            }
            y += stepY
        }
        return samples
    }

    static AverageColor(region, grid := 5) {
        samples := PixelCapture.SampleRegion(region, grid)
        if (samples.Length = 0)
            return "0x000000"
        r := 0
        g := 0
        b := 0
        for _, sample in samples {
            rgb := HexToRgb(sample["color"])
            r += rgb["r"]
            g += rgb["g"]
            b += rgb["b"]
        }
        count := samples.Length
        return "0x" Format("{:02X}{:02X}{:02X}", Round(r / count), Round(g / count), Round(b / count))
    }
}

get_pixel(x, y) {
    return PixelCapture.GetPixel(x, y)
}
