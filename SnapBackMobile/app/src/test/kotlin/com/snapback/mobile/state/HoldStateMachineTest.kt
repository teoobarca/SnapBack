package com.snapback.mobile.state

import org.junit.Assert.*
import org.junit.Test

class HoldStateMachineTest {
    @Test fun initialStateIsIdle() {
        assertEquals(HoldState.Idle, HoldStateMachine(ttlMs = 1000L).state)
    }

    @Test fun attentionWithPassingGateEntersHold() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        val r = sm.onAttention(gatePasses = true, hookKind = "Stop", nowMs = 1000L)
        assertEquals(TransitionEffect.LockAndArmTimer, r)
        assertEquals(HoldState.Hold, sm.state)
    }

    @Test fun attentionWithFailingGateDoesNothing() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        val r = sm.onAttention(gatePasses = false, hookKind = "Stop", nowMs = 1000L)
        assertEquals(TransitionEffect.Ignore, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun resumeExitsHoldAndCancelsTimer() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onResume(2000L)
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun ttlTimeoutExitsHold() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onTtlTick(nowMs = 2001L)
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun heartbeatMissExitsHold() {
        val sm = HoldStateMachine(ttlMs = 1_000_000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onHeartbeatMiss()
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }

    @Test fun userPresentDuringHoldRelocks() {
        val sm = HoldStateMachine(ttlMs = 1_000_000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onUserPresent()
        assertEquals(TransitionEffect.RelockAfterGrace, r)
        assertEquals(HoldState.Hold, sm.state)
    }

    @Test fun userPresentWhileIdleIgnored() {
        val sm = HoldStateMachine(ttlMs = 1000L)
        val r = sm.onUserPresent()
        assertEquals(TransitionEffect.Ignore, r)
    }

    @Test fun manualReleaseExitsHold() {
        val sm = HoldStateMachine(ttlMs = 1_000_000L)
        sm.onAttention(true, "Stop", 1000L)
        val r = sm.onManualRelease()
        assertEquals(TransitionEffect.UnlockAndCancelTimer, r)
        assertEquals(HoldState.Idle, sm.state)
    }
}
