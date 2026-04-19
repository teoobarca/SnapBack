package com.snapback.mobile.lock

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * Sole purpose: call `performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)` when
 * `LockDriver` requests. Does not subscribe to any event types.
 */
class SnapBackAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // no-op
    }

    override fun onInterrupt() {
        // no-op
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        @Volatile var instance: SnapBackAccessibilityService? = null
            private set

        fun lockViaAccessibility(): Boolean {
            val svc = instance ?: return false
            return svc.performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
    }
}
