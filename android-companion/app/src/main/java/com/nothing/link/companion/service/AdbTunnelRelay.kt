package com.nothing.link.companion.service

import android.util.Log
import kotlinx.coroutines.*
import org.webrtc.DataChannel
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket
import java.nio.ByteBuffer

class AdbTunnelRelay(
    private val dataChannel: DataChannel,
    private val onTunnelClosed: () -> Unit
) : DataChannel.Observer {

    companion object {
        private const val TAG = "NothingLink:AdbRelay"
        private const val ADB_PORT = 5555
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var adbSocket: Socket? = null
    private var outputStream: OutputStream? = null

    init {
        dataChannel.registerObserver(this)
        start()
    }

    private fun start() {
        scope.launch {
            try {
                Log.i(TAG, "Connecting to local ADB daemon on 127.0.0.1:$ADB_PORT...")
                val socket = Socket("127.0.0.1", ADB_PORT).apply {
                    tcpNoDelay = true
                    sendBufferSize = 64 * 1024
                    receiveBufferSize = 64 * 1024
                }
                adbSocket = socket
                outputStream = socket.getOutputStream()
                Log.i(TAG, "Connected to local ADB daemon on 127.0.0.1:$ADB_PORT")

                val inputStream: InputStream = socket.getInputStream()
                val buffer = ByteArray(32 * 1024)

                while (isActive && !socket.isClosed) {
                    val bytesRead = inputStream.read(buffer)
                    if (bytesRead == -1) break

                    val byteBuffer = ByteBuffer.wrap(buffer, 0, bytesRead)
                    val dataBuffer = DataChannel.Buffer(byteBuffer, true)
                    dataChannel.send(dataBuffer)
                }
            } catch (e: Exception) {
                Log.w(TAG, "AdbTunnelRelay loop error: ${e.message}")
            } finally {
                stop()
            }
        }
    }

    override fun onMessage(buffer: DataChannel.Buffer) {
        scope.launch {
            try {
                val bytes = ByteArray(buffer.data.remaining())
                buffer.data.get(bytes)
                outputStream?.write(bytes)
                outputStream?.flush()
            } catch (e: Exception) {
                Log.w(TAG, "Error writing data to local ADB: ${e.message}")
            }
        }
    }

    override fun onBufferedAmountChange(previousAmount: Long) {}

    override fun onStateChange() {
        Log.i(TAG, "adb-bridge DataChannel state: ${dataChannel.state()}")
        if (dataChannel.state() == DataChannel.State.CLOSED) {
            stop()
        }
    }

    fun stop() {
        scope.cancel()
        try {
            adbSocket?.close()
        } catch (_: Exception) {}
        adbSocket = null
        outputStream = null
        onTunnelClosed()
        Log.i(TAG, "AdbTunnelRelay stopped.")
    }
}
