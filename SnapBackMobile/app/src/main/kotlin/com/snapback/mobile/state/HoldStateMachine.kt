package com.snapback.mobile.state

enum class HoldState { Idle, Hold }

enum class TransitionEffect {
    Ignore,
    LockAndArmTimer,
    UnlockAndCancelTimer,
    RelockAfterGrace
}

class HoldStateMachine(private val ttlMs: Long) {
    var state: HoldState = HoldState.Idle
        private set
    private var holdStartedAt: Long = 0L

    fun onAttention(gatePasses: Boolean, hookKind: String, nowMs: Long): TransitionEffect {
        if (state == HoldState.Hold) return TransitionEffect.Ignore
        if (!gatePasses) return TransitionEffect.Ignore
        state = HoldState.Hold
        holdStartedAt = nowMs
        return TransitionEffect.LockAndArmTimer
    }

    fun onResume(nowMs: Long): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }

    fun onTtlTick(nowMs: Long): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        if (nowMs - holdStartedAt < ttlMs) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }

    fun onHeartbeatMiss(): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }

    fun onUserPresent(): TransitionEffect {
        return if (state == HoldState.Hold) TransitionEffect.RelockAfterGrace
               else TransitionEffect.Ignore
    }

    fun onManualRelease(): TransitionEffect {
        if (state != HoldState.Hold) return TransitionEffect.Ignore
        state = HoldState.Idle
        return TransitionEffect.UnlockAndCancelTimer
    }
}
