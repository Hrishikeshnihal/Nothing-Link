package com.nothing.link.companion.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.*
import org.webrtc.*

class ScreenCaptureService : Service() {

    companion object {
        private const val TAG = "NothingLink:WebRtc"
        private const val CHANNEL_ID = "nothing_link_stream"
        private const val NOTIF_ID = 2001
        var isStreaming = false
            private set
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var dataChannel: DataChannel? = null
    private var adbRelay: AdbTunnelRelay? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()

        val offerSdp = intent?.getStringExtra("EXTRA_OFFER_SDP")
        val sessionId = intent?.getStringExtra("EXTRA_SESSION_ID")

        if (!offerSdp.isNullOrBlank() && !sessionId.isNullOrBlank()) {
            initWebRtcDataTunnel(sessionId, offerSdp)
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Nothing Link Cloud Bridge",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Maintains WebRTC ADB Data Tunnel with Nothing Link PC"
        }
        nm.createNotificationChannel(channel)
    }

    private fun startForegroundNotification() {
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Nothing Link • Cloud Tunnel Active")
            .setContentText("Connected to PC via 5G WebRTC mesh")
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setOngoing(true)
            .build()
        startForeground(NOTIF_ID, notification)
    }

    private fun initWebRtcDataTunnel(sessionId: String, offerSdp: String) {
        scope.launch(Dispatchers.Default) {
            try {
                Log.i(TAG, "Initializing WebRTC Data-Only pipeline (ADB bridge)...")

                PeerConnectionFactory.initialize(
                    PeerConnectionFactory.InitializationOptions.builder(applicationContext)
                        .setEnableInternalTracer(false)
                        .createInitializationOptions()
                )

                peerConnectionFactory = PeerConnectionFactory.builder()
                    .createPeerConnectionFactory()

                val iceServers = listOf(
                    PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
                    PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer(),
                    PeerConnection.IceServer.builder("stun:stun.cloudflare.com:3478").createIceServer()
                )

                val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
                    sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
                    continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
                }

                peerConnection = peerConnectionFactory?.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
                    override fun onSignalingChange(state: PeerConnection.SignalingState?) {}
                    override fun onIceConnectionChange(state: PeerConnection.IceConnectionState?) {
                        Log.i(TAG, "ICE Connection State: $state")
                    }
                    override fun onIceConnectionReceivingChange(receiving: Boolean) {}
                    override fun onIceGatheringChange(state: PeerConnection.IceGatheringState?) {}
                    override fun onIceCandidate(candidate: IceCandidate?) {}
                    override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {}
                    override fun onAddStream(stream: MediaStream?) {}
                    override fun onRemoveStream(stream: MediaStream?) {}
                    override fun onDataChannel(dc: DataChannel?) {
                        Log.i(TAG, "Received remote DataChannel: ${dc?.label()}")
                        if (dc?.label() == "adb-bridge") {
                            setupDataChannel(dc)
                        }
                    }
                    override fun onRenegotiationNeeded() {}
                    override fun onAddTrack(receiver: RtpReceiver?, streams: Array<out MediaStream>?) {}
                })

                // Set Remote Description (Offer)
                val sessionDesc = SessionDescription(SessionDescription.Type.OFFER, offerSdp)
                peerConnection?.setRemoteDescription(object : SdpObserver {
                    override fun onCreateSuccess(desc: SessionDescription?) {}
                    override fun onSetSuccess() {
                        Log.i(TAG, "Offer SDP set successfully. Creating Answer SDP...")
                        createAndUploadAnswer(sessionId)
                    }
                    override fun onCreateFailure(error: String?) {
                        Log.e(TAG, "Failed to set remote description: $error")
                    }
                    override fun onSetFailure(error: String?) {
                        Log.e(TAG, "Failed to set remote description: $error")
                    }
                }, sessionDesc)

            } catch (e: Exception) {
                Log.e(TAG, "Failed to initialize WebRTC data-only pipeline: ${e.message}", e)
            }
        }
    }

    private fun createAndUploadAnswer(sessionId: String) {
        val constraints = MediaConstraints()
        peerConnection?.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(answerDesc: SessionDescription?) {
                if (answerDesc == null) return
                peerConnection?.setLocalDescription(object : SdpObserver {
                    override fun onCreateSuccess(p0: SessionDescription?) {}
                    override fun onSetSuccess() {
                        Log.i(TAG, "Local Answer SDP set. Uploading to Firestore...")
                        uploadAnswerToFirestore(sessionId, answerDesc.description)
                    }
                    override fun onCreateFailure(p0: String?) {}
                    override fun onSetFailure(p0: String?) {}
                }, answerDesc)
            }
            override fun onSetSuccess() {}
            override fun onCreateFailure(error: String?) {
                Log.e(TAG, "Failed to create answer SDP: $error")
            }
            override fun onSetFailure(error: String?) {}
        }, constraints)
    }

    private fun uploadAnswerToFirestore(sessionId: String, answerSdp: String) {
        val auth = FirebaseAuth.getInstance()
        val uid = auth.currentUser?.uid ?: return
        val db = FirebaseFirestore.getInstance()

        db.collection("users").document(uid)
            .collection("sessions").document(sessionId)
            .update(
                mapOf(
                    "answerSdp" to answerSdp,
                    "state" to "APPROVED"
                )
            ).addOnSuccessListener {
                Log.i(TAG, "Successfully uploaded WebRTC Answer SDP to Firestore.")
                isStreaming = true
            }.addOnFailureListener { e ->
                Log.e(TAG, "Failed to upload answer to Firestore: ${e.message}")
            }
    }

    private fun setupDataChannel(dc: DataChannel) {
        dataChannel = dc
        adbRelay = AdbTunnelRelay(dc) {
            Log.i(TAG, "ADB Tunnel Relay ended.")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        isStreaming = false
        adbRelay?.stop()
        dataChannel?.close()
        peerConnection?.close()
        peerConnectionFactory?.dispose()
        scope.cancel()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
