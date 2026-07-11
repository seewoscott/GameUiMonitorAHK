#Requires AutoHotkey v2.0
#SingleInstance Force

SetWorkingDir(A_ScriptDir)

for _, arg in A_Args {
    if (arg = "--check")
        ExitApp(0)
}

global Demo := DemoTarget()
Demo.Start()

class DemoTarget {
    __New() {
        this.gui := ""
        this.hp := ""
        this.buff := ""
        this.skill := ""
        this.buffOn := true
        this.skillOn := true
        this.hpValue := 85
    }

    Start() {
        this.gui := Gui("+AlwaysOnTop -Caption +ToolWindow", "SDGO画面监测助手 测试窗口")
        this.gui.BackColor := "202020"
        this.gui.SetFont("s10 cFFFFFF", "Microsoft YaHei UI")
        this.gui.Add("Text", "x0 y0 w520 h32 Center BackgroundTrans", "SDGO画面监测助手 测试窗口")
        this.gui.Add("Text", "x40 y42 w80 h20", "HP")
        this.gui.Add("Progress", "x40 y64 w260 h22 Background551010 cE03030 Range0-100", this.hpValue)
        this.gui.Add("Text", "x40 y96 w80 h20", "BUFF")
        this.buff := this.gui.Add("Progress", "x47 y113 w42 h42 Background303030 cFF8800 Range0-100", 100)
        this.gui.Add("Text", "x120 y96 w80 h20", "SKILL")
        this.skill := this.gui.Add("Progress", "x127 y113 w42 h42 Background303030 c20D060 Range0-100", 100)
        this.gui.Add("Text", "x210 y96 w170 h20", "提示：拖动下方区域移动")
        drag := this.gui.Add("Text", "x40 y220 w440 h46 Center BackgroundTrans", "这是模拟游戏窗口：颜色块会自动变化，用于测试 Fast / Medium / Slow 检测。")
        drag.OnEvent("Click", ObjBindMethod(this, "StartDrag"))
        this.gui.OnEvent("Close", (*) => ExitApp())
        this.gui.Show("x120 y120 w520 h300")

        SetTimer(ObjBindMethod(this, "ToggleBuff"), 1800)
        SetTimer(ObjBindMethod(this, "ToggleSkill"), 950)
        SetTimer(ObjBindMethod(this, "PulseHp"), 700)
    }

    StartDrag(*) {
        PostMessage(0xA1, 2,,, "ahk_id " this.gui.Hwnd)
    }

    ToggleBuff(*) {
        this.buffOn := !this.buffOn
        if this.buffOn {
            this.buff.Opt("cFF8800")
            this.buff.Value := 100
        } else {
            this.buff.Opt("c606060")
            this.buff.Value := 100
        }
    }

    ToggleSkill(*) {
        this.skillOn := !this.skillOn
        if this.skillOn {
            this.skill.Opt("c20D060")
            this.skill.Value := 100
        } else {
            this.skill.Opt("c505050")
            this.skill.Value := 100
        }
    }

    PulseHp(*) {
        this.hpValue -= 3
        if (this.hpValue < 45)
            this.hpValue := 90
    }
}
