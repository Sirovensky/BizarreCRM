package com.bizarreelectronics.crm.ui.screens.camera

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

// TODO: Integrate CameraX for real photo capture
// Dependencies needed in build.gradle:
//   implementation("androidx.camera:camera-camera2:1.4.x")
//   implementation("androidx.camera:camera-lifecycle:1.4.x")
//   implementation("androidx.camera:camera-view:1.4.x")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PhotoCaptureScreen(
    ticketId: Long,
    onBack: () -> Unit,
) {
    var selectedType by remember { mutableStateOf("pre") }
    var photoCount by remember { mutableIntStateOf(0) }
    var showSuccessSnackbar by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(showSuccessSnackbar) {
        if (showSuccessSnackbar) {
            snackbarHostState.showSnackbar("Photo captured ($selectedType-condition)")
            showSuccessSnackbar = false
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Photos - Ticket #$ticketId") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (photoCount > 0) {
                        Badge(modifier = Modifier.padding(end = 16.dp)) {
                            Text("$photoCount")
                        }
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Type selector (pre/post condition)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FilterChip(
                    selected = selectedType == "pre",
                    onClick = { selectedType = "pre" },
                    label = { Text("Pre-Condition") },
                    leadingIcon = if (selectedType == "pre") {
                        { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                    } else {
                        null
                    },
                    modifier = Modifier.weight(1f),
                )
                FilterChip(
                    selected = selectedType == "post",
                    onClick = { selectedType = "post" },
                    label = { Text("Post-Condition") },
                    leadingIcon = if (selectedType == "post") {
                        { Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                    } else {
                        null
                    },
                    modifier = Modifier.weight(1f),
                )
            }

            // Camera preview placeholder
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .background(Color.Black),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.CameraAlt,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = Color.White.copy(alpha = 0.7f),
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "CameraX preview\n(integration pending)",
                        color = Color.White.copy(alpha = 0.5f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }

            // Capture controls
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Gallery picker
                IconButton(onClick = { /* TODO: Open gallery picker */ }) {
                    Icon(
                        Icons.Default.PhotoLibrary,
                        contentDescription = "Gallery",
                        modifier = Modifier.size(32.dp),
                    )
                }

                // Capture button
                IconButton(
                    onClick = {
                        // TODO: Capture photo via CameraX and upload to server
                        photoCount++
                        showSuccessSnackbar = true
                    },
                    modifier = Modifier
                        .size(72.dp)
                        .border(
                            width = 4.dp,
                            color = MaterialTheme.colorScheme.primary,
                            shape = CircleShape,
                        ),
                ) {
                    Surface(
                        shape = CircleShape,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(56.dp),
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                Icons.Default.CameraAlt,
                                contentDescription = "Capture",
                                tint = MaterialTheme.colorScheme.onPrimary,
                                modifier = Modifier.size(28.dp),
                            )
                        }
                    }
                }

                // Switch camera
                IconButton(onClick = { /* TODO: Switch front/back camera */ }) {
                    Icon(
                        Icons.Default.FlipCameraAndroid,
                        contentDescription = "Switch Camera",
                        modifier = Modifier.size(32.dp),
                    )
                }
            }
        }
    }
}
