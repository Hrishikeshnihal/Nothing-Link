package com.nothing.link.companion.service

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent

class NothingAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "NothingLink:A11y"
        var instance: NothingAccessibilityService? = null
            private set
    }

    private val handler = Handler(Looper.getMainLooper())

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.i(TAG, "Nothing Link Accessibility Service Connected.")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Auto-detect keyguard / bouncer if needed
    }

    override fun onInterrupt() {
        Log.w(TAG, "Accessibility Service interrupted.")
    }

    /**
     * Finds and toggles the Wi-Fi Hotspot switch on screen automatically.
     */
    fun toggleHotspotSwitch(): Boolean {
        try {
            val root = rootInActiveWindow ?: return false
            val textQueries = listOf("Wi-Fi hotspot", "Portable hotspot", "Hotspot", "hotspot")
            for (query in textQueries) {
                val nodes = root.findAccessibilityNodeInfosByText(query)
                for (node in nodes) {
                    var targetNode: android.view.accessibility.AccessibilityNodeInfo? = node
                    while (targetNode != null && !targetNode.isClickable) {
                        targetNode = targetNode.parent
                    }
                    if (targetNode != null && targetNode.isClickable) {
                        Log.i(TAG, "Found clickable hotspot node: ${node.text}. Performing click...")
                        targetNode.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in toggleHotspotSwitch: ${e.message}")
        }
        return false
    }

    override fun onDestroy() {
        super.onDestroy()
        if (instance == this) instance = null
        Log.i(TAG, "Accessibility Service destroyed.")
    }

    /**
     * Strokes pattern 159873 (1 -> 5 -> 9 -> 8 -> 7 -> 5 -> 3)
     */
    fun performAutoUnlock(onComplete: ((Boolean) -> Unit)? = null) {
        Log.i(TAG, "Executing auto-unlock for pattern 159873...")

        val path = Path().apply {
            // Dot 1
            moveTo(247f, 1163f)
            // Dot 5
            lineTo(540f, 1456f)
            // Dot 9
            lineTo(833f, 1750f)
            // Dot 8
            lineTo(540f, 1750f)
            // Dot 7
            lineTo(247f, 1750f)
            // Dot 5
            lineTo(540f, 1456f)
            // Dot 3
            lineTo(833f, 1163f)
        }

        val stroke = GestureDescription.StrokeDescription(path, 0, 450)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()

        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                Log.i(TAG, "Pattern 159873 stroke successfully dispatched.")
                onComplete?.invoke(true)
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                Log.w(TAG, "Pattern 159873 stroke was cancelled.")
                onComplete?.invoke(false)
            }
        }, handler)
    }
}
