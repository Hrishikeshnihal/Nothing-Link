package com.nothing.link.companion.service

import android.content.pm.PackageManager
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

object ShizukuManager {
    private const val TAG = "NothingLink:Shizuku"
    const val SHIZUKU_REQUEST_CODE = 1002

    fun isShizukuRunning(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Exception) {
            Log.w(TAG, "Shizuku ping failed: ${e.message}")
            false
        }
    }

    fun hasShizukuPermission(): Boolean {
        return try {
            if (!isShizukuRunning()) return false
            if (Shizuku.isPreV11()) {
                false
            } else {
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
            }
        } catch (e: Exception) {
            Log.w(TAG, "Shizuku permission check failed: ${e.message}")
            false
        }
    }

    fun requestShizukuPermission() {
        try {
            if (isShizukuRunning() && !hasShizukuPermission()) {
                Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting Shizuku permission: ${e.message}")
        }
    }

    fun executeCommand(command: String): Result<String> {
        if (!hasShizukuPermission()) {
            return Result.failure(IllegalStateException("Shizuku permission not granted."))
        }
        return try {
            val process = Shizuku.newProcess(arrayOf("sh", "-c", command), null, null)
            val output = BufferedReader(InputStreamReader(process.inputStream)).use { it.readText() }
            val error = BufferedReader(InputStreamReader(process.errorStream)).use { it.readText() }
            val exitCode = process.waitFor()

            if (exitCode == 0) {
                Result.success(output.trim())
            } else {
                Result.failure(RuntimeException("Command failed (exit $exitCode): $error"))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing Shizuku command: ${e.message}", e)
            Result.failure(e)
        }
    }

    fun setHotspotEnabled(enabled: Boolean): Result<String> {
        val action = if (enabled) "enabled" else "disabled"
        Log.i(TAG, "Toggling hotspot ($action) via Shizuku...")
        val cmd = "am start -a android.settings.TETHER_SETTINGS; sleep 0.5; input tap 948 1066; sleep 0.4; input keyevent 3"
        return executeCommand(cmd)
    }

    fun enableAdbTcpip(): Result<String> {
        Log.i(TAG, "Enabling ADB over TCP/IP 5555 via Shizuku...")
        return executeCommand("setprop service.adb.tcp.port 5555; stop adbd; start adbd")
    }
}
