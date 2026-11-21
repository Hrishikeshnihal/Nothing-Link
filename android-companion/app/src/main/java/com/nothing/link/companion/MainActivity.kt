package com.nothing.link.companion

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nothing.link.companion.service.CloudService
import com.nothing.link.companion.service.NothingAccessibilityService
import com.nothing.link.companion.service.ShizukuManager
import kotlinx.coroutines.*

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Start Cloud Sync Service in background
        val serviceIntent = Intent(this, CloudService::class.java)
        startForegroundService(serviceIntent)

        setContent {
            NothingLinkApp(this)
        }
    }
}

@Composable
fun NothingLinkApp(context: Context) {
    var hasShizuku by remember { mutableStateOf(ShizukuManager.hasShizukuPermission()) }
    var isShizukuRunning by remember { mutableStateOf(ShizukuManager.isShizukuRunning()) }
    var hasA11y by remember { mutableStateOf(NothingAccessibilityService.instance != null) }
    var isHotspotOn by remember { mutableStateOf(CloudService.isHotspotActive) }
    var awayModeBlackScreen by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    // Periodic status refresh
    LaunchedEffect(Unit) {
        while (true) {
            hasShizuku = ShizukuManager.hasShizukuPermission()
            isShizukuRunning = ShizukuManager.isShizukuRunning()
            hasA11y = NothingAccessibilityService.instance != null
            isHotspotOn = CloudService.isHotspotActive
            delay(1500)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF070709))
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(20.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Header Pill
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.06f))
                    .border(1.dp, Color.White.copy(alpha = 0.12f), CircleShape)
                    .padding(horizontal = 18.dp, vertical = 14.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(Color(0xFFD71921))
                    )
                    Spacer(modifier = Modifier.width(10.dp))
                    Text(
                        text = "NOTHING LINK",
                        color = Color.White,
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp
                    )
                }
                Text(
                    text = "NOS 5.0",
                    color = Color.White.copy(alpha = 0.5f),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 12.sp
                )
            }

            // Cloud Presence Card
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(Color.White.copy(alpha = 0.08f), Color.White.copy(alpha = 0.02f))
                        )
                    )
                    .border(1.dp, Color.White.copy(alpha = 0.12f), RoundedCornerShape(24.dp))
                    .padding(20.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        text = "CLOUD LINK • nihilhrishikesh@gmail.com",
                        color = Color(0xFF34D399),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = "Device: ${CloudService.currentDeviceId}",
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium
                    )
                    Text(
                        text = "Transport: ${CloudService.currentTransport} • IP: ${CloudService.currentLocalIp}",
                        color = Color.White.copy(alpha = 0.6f),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 12.sp
                    )
                }
            }

            // ONE-TAP HOTSPOT CARD
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(if (isHotspotOn) Color(0xFF10B981) else Color(0xFFD71921))
                    .clickable {
                        if (!hasShizuku) {
                            Toast.makeText(context, "Please grant Shizuku permission first!", Toast.LENGTH_SHORT).show()
                            ShizukuManager.requestShizukuPermission()
                        } else {
                            val targetState = !isHotspotOn
                            val res = ShizukuManager.setHotspotEnabled(targetState)
                            if (res.isSuccess) {
                                isHotspotOn = targetState
                                Toast.makeText(
                                    context,
                                    if (targetState) "Wi-Fi Hotspot Activated!" else "Hotspot Turned Off",
                                    Toast.LENGTH_SHORT
                                ).show()
                            } else {
                                // Accessibility fallback
                                val a11y = NothingAccessibilityService.instance
                                if (a11y != null) {
                                    val tetherIntent = Intent("android.settings.TETHER_SETTINGS").apply {
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    context.startActivity(tetherIntent)
                                    scope.launch {
                                        delay(600)
                                        a11y.toggleHotspotSwitch()
                                        delay(500)
                                        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                                            addCategory(Intent.CATEGORY_HOME)
                                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                        }
                                        context.startActivity(homeIntent)
                                    }
                                    isHotspotOn = targetState
                                    Toast.makeText(context, "Hotspot Toggled!", Toast.LENGTH_SHORT).show()
                                } else {
                                    Toast.makeText(context, "Error: ${res.exceptionOrNull()?.message}", Toast.LENGTH_LONG).show()
                                }
                            }
                        }
                    }
                    .padding(22.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        text = "1-TAP HOTSPOT CONTROL",
                        color = Color.White.copy(alpha = 0.8f),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = if (isHotspotOn) "HOTSPOT ACTIVE • 2ms LATENCY" else "TURN ON WI-FI HOTSPOT",
                        color = Color.White,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        text = if (isHotspotOn) "Tap to turn off. Laptop can connect to phone Wi-Fi." else "Turns on mobile hotspot without touching settings.",
                        color = Color.White.copy(alpha = 0.85f),
                        fontSize = 12.sp
                    )
                }
            }

            // Permissions Card (Shizuku + Accessibility)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(24.dp))
                    .padding(20.dp)
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    // Shizuku Row
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                if (!hasShizuku) ShizukuManager.requestShizukuPermission()
                            },
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = "Shizuku Shell Access",
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = if (hasShizuku) "Authorized (Enables remote hotspot & adb)" else if (isShizukuRunning) "Running • Tap to grant" else "Not running (Open Shizuku app)",
                                color = Color.White.copy(alpha = 0.5f),
                                fontSize = 12.sp
                            )
                        }
                        Text(
                            text = if (hasShizuku) "ACTIVE" else "GRANT",
                            color = if (hasShizuku) Color(0xFF34D399) else Color(0xFFD71921),
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp
                        )
                    }

                    Divider(color = Color.White.copy(alpha = 0.08f))

                    // Accessibility Row
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            },
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column {
                            Text(
                                text = "Auto-Unlock (Pattern 159873)",
                                color = Color.White,
                                fontSize = 15.sp,
                                fontWeight = FontWeight.Medium
                            )
                            Text(
                                text = if (hasA11y) "Active • Screen automatically unlocks" else "Tap to enable in Accessibility Settings",
                                color = Color.White.copy(alpha = 0.5f),
                                fontSize = 12.sp
                            )
                        }
                        Text(
                            text = if (hasA11y) "ACTIVE" else "ENABLE",
                            color = if (hasA11y) Color(0xFF34D399) else Color(0xFFD71921),
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp
                        )
                    }
                }
            }

            // OLED Away Mode (Screen Off Display)
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color.White.copy(alpha = 0.05f))
                    .border(1.dp, Color.White.copy(alpha = 0.1f), RoundedCornerShape(24.dp))
                    .clickable { awayModeBlackScreen = true }
                    .padding(20.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column {
                        Text(
                            text = "Away Mode (OLED Pure Black)",
                            color = Color.White,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium
                        )
                        Text(
                            text = "Turns display completely black while mirroring to PC",
                            color = Color.White.copy(alpha = 0.5f),
                            fontSize = 12.sp
                        )
                    }
                    Text(
                        text = "BLACKOUT",
                        color = Color.White.copy(alpha = 0.6f),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 11.sp
                    )
                }
            }
        }

        // Full Screen Black OLED Overlay (Away Mode)
        if (awayModeBlackScreen) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
                    .clickable { awayModeBlackScreen = false }
            ) {
                Text(
                    text = "AWAY MODE ACTIVE • TAP ANYWHERE TO WAKE",
                    color = Color.White.copy(alpha = 0.2f),
                    fontFamily = FontFamily.Monospace,
                    fontSize = 11.sp
                )
            }
        }
    }
}
