package com.snapback.mobile.state

import org.junit.Assert.*
import org.junit.Test

class ScreenStateGateTest {
    @Test fun onlyFiresWhenInteractiveAndUnlocked() {
        assertTrue(ScreenStateGate.passes(isInteractive = true, isLocked = false))
        assertFalse(ScreenStateGate.passes(isInteractive = false, isLocked = false))
        assertFalse(ScreenStateGate.passes(isInteractive = true, isLocked = true))
        assertFalse(ScreenStateGate.passes(isInteractive = false, isLocked = true))
    }
}
