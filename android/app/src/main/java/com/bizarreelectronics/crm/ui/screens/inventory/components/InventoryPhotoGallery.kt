package com.bizarreelectronics.crm.ui.screens.inventory.components

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.bizarreelectronics.crm.ui.components.shared.BrandCard

/**
 * Photo gallery with pinch-to-zoom for an inventory item (L1083).
 *
 * Displays item photos in a [HorizontalPager]. Each page supports pinch-to-zoom
 * via [detectTransformGestures] (no external library required). When the item has
 * no photos, a "No photos" placeholder with an upload button is shown.
 *
 * Upload triggers [onUploadPhoto] which the caller should route through the
 * existing [MultipartUpload] work manager.
 *
 * @param photoUrls     List of photo URLs to display. May be empty.
 * @param onUploadPhoto Invoked when the user taps the upload button. Caller
 *                      launches the image picker / work manager.
 * @param modifier      Applied to the root [BrandCard].
 */
@Composable
fun InventoryPhotoGallery(
    photoUrls: List<String>,
    onUploadPhoto: () -> Unit,
    modifier: Modifier = Modifier,
    /** §6.3: When true, show an upload progress indicator instead of the add button. */
    isUploading: Boolean = false,
) {
    BrandCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.Image,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        "Photos${if (photoUrls.isNotEmpty()) " (${photoUrls.size})" else ""}",
                        style = MaterialTheme.typography.titleSmall,
                    )
                }

                // §6.3: Show spinner while upload is in-flight; button otherwise.
                if (isUploading) {
                    Box(
                        modifier = Modifier.size(48.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                } else {
                    IconButton(onClick = onUploadPhoto) {
                        Icon(
                            Icons.Default.AddPhotoAlternate,
                            contentDescription = "Upload photo",
                            tint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(8.dp))

            if (photoUrls.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(160.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (isUploading) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            CircularProgressIndicator()
                            Text(
                                "Uploading photo…",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        Text(
                            "No photos yet. Tap + to upload.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            } else {
                val pagerState = rememberPagerState(pageCount = { photoUrls.size })

                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(220.dp),
                ) { page ->
                    ZoomablePhoto(
                        url = photoUrls[page],
                        modifier = Modifier.fillMaxSize(),
                    )
                }

                if (photoUrls.size > 1) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp),
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        repeat(photoUrls.size) { idx ->
                            val selected = pagerState.currentPage == idx
                            Surface(
                                shape = MaterialTheme.shapes.extraSmall,
                                color = if (selected) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                                modifier = Modifier
                                    .padding(horizontal = 2.dp)
                                    .size(if (selected) 8.dp else 6.dp),
                            ) {}
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ZoomablePhoto(
    url: String,
    modifier: Modifier = Modifier,
) {
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }

    Box(
        modifier = modifier
            .background(Color.Black)
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(1f, 5f)
                    // Clamp pan so the image can't be dragged fully off-screen.
                    val maxX = (size.width * (scale - 1f)) / 2f
                    val maxY = (size.height * (scale - 1f)) / 2f
                    offset = Offset(
                        x = (offset.x + pan.x).coerceIn(-maxX, maxX),
                        y = (offset.y + pan.y).coerceIn(-maxY, maxY),
                    )
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        AsyncImage(
            model = url,
            contentDescription = "Item photo",
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer(
                    scaleX = scale,
                    scaleY = scale,
                    translationX = offset.x,
                    translationY = offset.y,
                ),
        )
    }
}
