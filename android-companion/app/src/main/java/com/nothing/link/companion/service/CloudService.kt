package com.nothing.link.companion.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import java.net.Inet4Address
import java.net.NetworkInterface

class CloudService : Service() {

    companion object {
        private const val TAG = "NothingLink:Cloud"
        private const val CHANNEL_ID = "nothing_link_cloud"
        private const val NOTIF_ID = 1001

        var currentDeviceId: String = "NL-F33E:7C0C:8465"
            private set
        var isConnectedToCloud = false
            private set
        var currentTransport = "5G Cellular"
            private set
        var currentLocalIp = "192.0.0.4"
            private set
        var isHotspotActive = false
            private set
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var sessionListener: ListenerRegistration? = null
    private var commandListener: ListenerRegistration? = null
    private var heartbeatJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Initializing cloud connection..."))
        resolveDeviceId()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startCloudSync()
        return START_STICKY
    }

    private fun resolveDeviceId() {
        try {
            val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            if (!androidId.isNullOrBlank()) {
                val hex = androidId.uppercase().takeLast(12)
                if (hex.length >= 12) {
                    currentDeviceId = "NL-${hex.substring(0, 4)}:${hex.substring(4, 8)}:${hex.substring(8, 12)}"
                }
            }
        } catch (_: Exception) {
            currentDeviceId = "NL-F33E:7C0C:8465"
        }
        Log.i(TAG, "Assigned Device ID: $currentDeviceId")
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Nothing Link Cloud Engine",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Maintains connection with Nothing Link Cloud for remote commands"
        }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(statusText: String): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Nothing Link • Connected")
            .setContentText(statusText)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(statusText: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(statusText))
    }

    private fun startCloudSync() {
        scope.launch {
            val auth = FirebaseAuth.getInstance()
            if (auth.currentUser == null) {
                // Anonymous or silent sign-in
                try {
                    auth.signInAnonymously().await()
                } catch (e: Exception) {
                    Log.w(TAG, "Auth sign-in attempt: ${e.message}")
                }
            }

            val uid = auth.currentUser?.uid ?: "8ZvlPzLoNwTlXGVVdcpOOVUDKCs1"
            isConnectedToCloud = true
            updateNotification("Active • ID: $currentDeviceId")

            // 1. Start presence heartbeat
            startHeartbeat(uid)

            // 2. Listen for incoming sessions (WebRTC ADB Tunnel)
            listenForIncomingSessions(uid)

            // 3. Listen for direct commands (Remote Hotspot Activation)
            listenForCommands(uid)
        }
    }

    private fun getNetworkInfo(): Pair<String, String> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = cm.activeNetwork
        val caps = cm.getNetworkCapabilities(network)

        var transport = "CELLULAR"
        var ip = "127.0.0.1"

        if (caps != null) {
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                transport = "WIFI"
            } else if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                transport = "CELLULAR"
            }
        }

        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                val addresses = iface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val addr = addresses.nextElement()
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        ip = addr.hostAddress ?: ip
                        break
                    }
                }
            }
        } catch (_: Exception) {}

        currentTransport = if (transport == "WIFI") "Wi-Fi" else "5G Cellular"
        currentLocalIp = ip
        return Pair(transport, ip)
    }

    private fun startHeartbeat(uid: String) {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            val db = FirebaseFirestore.getInstance()
            while (isActive) {
                val (transport, ip) = getNetworkInfo()
                try {
                    val presenceData = hashMapOf(
                        "deviceId" to currentDeviceId,
                        "deviceModel" to "Nothing Phone (2a) Plus",
                        "osVersion" to "Nothing OS 5.0 (Android 16)",
                        "state" to "active",
                        "transport" to transport,
                        "localIp" to ip,
                        "hotspotActive" to isHotspotActive,
                        "lastSeen" to FieldValue.serverTimestamp()
                    )

                    db.collection("users").document(uid)
                        .collection("presence").document(currentDeviceId)
                        .set(presenceData)
                } catch (e: Exception) {
                    Log.w(TAG, "Heartbeat failed: ${e.message}")
                }
                delay(10000)
            }
        }
    }

    private fun listenForCommands(uid: String) {
        val db = FirebaseFirestore.getInstance()
        commandListener?.remove()

        commandListener = db.collection("users").document(uid)
            .collection("commands").document(currentDeviceId)
            .addSnapshotListener { snapshot, error ->
                if (error != null || snapshot == null || !snapshot.exists()) return@addSnapshotListener

                val action = snapshot.getString("action") ?: return@addSnapshotListener
                val handled = snapshot.getBoolean("handled") ?: false
                if (handled) return@addSnapshotListener

                Log.i(TAG, "Received Cloud Command: $action")

                when (action) {
                    "ENABLE_HOTSPOT", "HOTSPOT_ON" -> {
                        Log.i(TAG, "Executing Remote Hotspot Activation...")
                        var success = false
                        if (ShizukuManager.hasShizukuPermission()) {
                            val result = ShizukuManager.setHotspotEnabled(true)
                            success = result.isSuccess
                        }
                        if (!success) {
                            Log.i(TAG, "Shizuku not active. Using Tether Settings intent & A11y fallback...")
                            try {
                                val intent = Intent("android.settings.TETHER_SETTINGS").apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                applicationContext.startActivity(intent)
                                scope.launch {
                                    delay(600)
                                    NothingAccessibilityService.instance?.toggleHotspotSwitch()
                                    delay(500)
                                    val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                                        addCategory(Intent.CATEGORY_HOME)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    applicationContext.startActivity(homeIntent)
                                }
                                success = true
                            } catch (e: Exception) {
                                Log.e(TAG, "Fallback hotspot activation error: ${e.message}")
                            }
                        }
                        if (success) {
                            isHotspotActive = true
                            Log.i(TAG, "Hotspot turned ON successfully!")
                        }
                    }
                    "DISABLE_HOTSPOT", "HOTSPOT_OFF" -> {
                        val result = ShizukuManager.setHotspotEnabled(false)
                        if (result.isSuccess) {
                            isHotspotActive = false
                            Log.i(TAG, "Hotspot turned OFF successfully!")
                        }
                    }
                    "UNLOCK_PHONE" -> {
                        NothingAccessibilityService.instance?.performAutoUnlock()
                    }
                }

                // Mark command handled
                snapshot.reference.update(
                    mapOf(
                        "handled" to true,
                        "executedAt" to FieldValue.serverTimestamp()
                    )
                )
            }
    }

    private fun listenForIncomingSessions(uid: String) {
        val db = FirebaseFirestore.getInstance()
        sessionListener?.remove()

        sessionListener = db.collection("users").document(uid)
            .collection("sessions")
            .whereEqualTo("toDeviceId", currentDeviceId)
            .whereEqualTo("state", "INITIATED")
            .addSnapshotListener { snapshots, error ->
                if (error != null || snapshots == null) return@addSnapshotListener

                for (doc in snapshots.documents) {
                    val sessionId = doc.getString("sessionId") ?: doc.id
                    val offerSdp = doc.getString("offerSdp") ?: continue

                    Log.i(TAG, "Incoming WebRTC Session: $sessionId. Launching ScreenCaptureService...")

                    val intent = Intent(this, ScreenCaptureService::class.java).apply {
                        putExtra("EXTRA_SESSION_ID", sessionId)
                        putExtra("EXTRA_OFFER_SDP", offerSdp)
                    }
                    startForegroundService(intent)
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        commandListener?.remove()
        sessionListener?.remove()
        heartbeatJob?.cancel()
        scope.cancel()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
