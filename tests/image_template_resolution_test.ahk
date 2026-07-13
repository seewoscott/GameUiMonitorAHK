#Requires AutoHotkey v2.0
#SingleInstance Force

#Include ..\core\utils.ahk
#Include ..\core\window.ahk
#Include ..\detectors\image_detector.ahk

testRoot := JoinPath(A_Temp, "monitor_template_resolution_" A_TickCount)
DirCreate(testRoot)
original := JoinPath(testRoot, "anchor.png")
profile1920 := JoinPath(testRoot, "anchor_1920x1080.png")
FileAppend("original", original, "UTF-8")
FileAppend("profile", profile1920, "UTF-8")

resolved := ImageDetector.ResolveTemplate(testRoot, "anchor.png", 1920, 1080)
if (resolved["path"] != profile1920 || resolved["candidates"].Length != 2)
    Fail(testRoot)

resolved := ImageDetector.ResolveTemplate(testRoot, "anchor.png", 2880, 1800)
if (resolved["path"] != original)
    Fail(testRoot)

FileDelete(profile1920)
resolved := ImageDetector.ResolveTemplate(testRoot, "anchor.png", 1920, 1080)
if (resolved["path"] != original)
    Fail(testRoot)

FileDelete(original)
resolved := ImageDetector.ResolveTemplate(testRoot, "anchor.png", 1920, 1080)
if (resolved["path"] != "" || resolved["candidates"].Length != 2)
    Fail(testRoot)
errorResult := ImageDetector.Detect(
    Map("template_path", "anchor.png", "tolerance", 0),
    Map("x", 0, "y", 0, "w", 1, "h", 1),
    testRoot,
    Map("w", 1920, "h", 1080)
)
if (errorResult["matched"] || !InStr(errorResult["error"], profile1920) || !InStr(errorResult["error"], original))
    Fail(testRoot)

DirDelete(testRoot, true)
ExitApp(0)

Fail(testRoot) {
    if DirExist(testRoot)
        DirDelete(testRoot, true)
    ExitApp(1)
}
