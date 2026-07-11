#Requires AutoHotkey v2.0

class ImageDetector {
    static Detect(element, region, root) {
        start := A_TickCount
        template := ResolveProjectPath(root, element["template_path"])
        if (template = "" || !FileExist(template)) {
            return Map(
                "matched", false,
                "score", 0.0,
                "color", "",
                "latency_ms", A_TickCount - start,
                "error", "模板图片不存在：" template
            )
        }

        variation := Round(Clamp(element["tolerance"], 0, 255))
        option := variation > 0 ? "*" variation " " template : template
        x1 := region["x"]
        y1 := region["y"]
        x2 := region["x"] + region["w"] - 1
        y2 := region["y"] + region["h"] - 1
        foundX := 0
        foundY := 0

        try {
            matched := ImageSearch(&foundX, &foundY, x1, y1, x2, y2, option)
            return Map(
                "matched", matched,
                "score", matched ? 1.0 : 0.0,
                "color", "",
                "latency_ms", A_TickCount - start,
                "error", "",
                "found_x", foundX,
                "found_y", foundY
            )
        } catch as err {
            return Map(
                "matched", false,
                "score", 0.0,
                "color", "",
                "latency_ms", A_TickCount - start,
                "error", "ImageSearch 执行失败：" err.Message
            )
        }
    }
}
