#Requires AutoHotkey v2.0

class ImageDetector {
    static Detect(element, region, root, displaySize := "") {
        start := A_TickCount
        if !IsObject(displaySize)
            displaySize := WindowManager.QueryPrimaryPhysicalSize()
        resolution := ImageDetector.ResolveTemplate(
            root,
            element["template_path"],
            displaySize["w"],
            displaySize["h"]
        )
        template := resolution["path"]
        if (template = "") {
            return Map(
                "matched", false,
                "score", 0.0,
                "color", "",
                "latency_ms", A_TickCount - start,
                "error", "模板图片不存在；已检查：" ImageDetector.JoinCandidates(resolution["candidates"])
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

    static ResolveTemplate(root, templatePath, screenWidth, screenHeight) {
        original := ResolveProjectPath(root, templatePath)
        candidates := []
        if (original = "")
            return Map("path", "", "candidates", candidates)

        SplitPath(original, &fileName, &dir, &extension, &nameNoExt)
        suffix := "_" Round(screenWidth) "x" Round(screenHeight)
        profileFile := nameNoExt suffix (extension != "" ? "." extension : "")
        profilePath := dir != "" ? JoinPath(dir, profileFile) : profileFile
        candidates.Push(profilePath)
        if (profilePath != original)
            candidates.Push(original)

        for _, candidate in candidates {
            if FileExist(candidate)
                return Map("path", candidate, "candidates", candidates)
        }
        return Map("path", "", "candidates", candidates)
    }

    static JoinCandidates(candidates) {
        text := ""
        for index, candidate in candidates
            text .= (index > 1 ? "；" : "") candidate
        return text != "" ? text : "（空路径）"
    }
}
