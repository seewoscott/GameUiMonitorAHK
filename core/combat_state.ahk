#Requires AutoHotkey v2.0

class CombatStateTracker {
    __New(enterFrames := 2, enterMs := 250, exitFrames := 3, exitMs := 500) {
        this.enterFrames := enterFrames
        this.enterMs := enterMs
        this.exitFrames := exitFrames
        this.exitMs := exitMs
        this.Reset()
    }

    Reset(stable := false) {
        this.stable := stable
        this.pending := ""
        this.pendingCount := 0
        this.pendingSince := 0
    }

    Update(candidate, now := A_TickCount) {
        candidate := candidate ? true : false
        changed := false
        if (candidate = this.stable) {
            this.pending := ""
            this.pendingCount := 0
            this.pendingSince := 0
            return Map("active", this.stable, "changed", false)
        }

        if (this.pending = "" || this.pending != candidate) {
            this.pending := candidate
            this.pendingCount := 1
            this.pendingSince := now
            return Map("active", this.stable, "changed", false)
        }

        this.pendingCount += 1
        requiredFrames := candidate ? this.enterFrames : this.exitFrames
        requiredMs := candidate ? this.enterMs : this.exitMs
        if (this.pendingCount >= requiredFrames && now - this.pendingSince >= requiredMs) {
            this.stable := candidate
            this.pending := ""
            this.pendingCount := 0
            this.pendingSince := 0
            changed := true
        }
        return Map("active", this.stable, "changed", changed)
    }
}
