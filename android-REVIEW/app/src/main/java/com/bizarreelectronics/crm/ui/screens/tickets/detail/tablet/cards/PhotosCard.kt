package com.bizarreelectronics.crm.ui.screens.tickets.detail.tablet.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import androidx.compose.ui.platform.LocalContext
import com.bizarreelectronics.crm.data.remote.dto.TicketPhoto

/**
 * Tablet ticket-detail Photos card.
 *
 * 4-up thumbnail grid; tap any cell opens the photo viewer (host
 * wires via [onOpenPhoto]). Header has a cream `+ Add` pill that
 * triggers [onAddPhoto] — host opens the existing photo capture /
 * gallery screen (the same path the phone Add Photo flow uses).
 *
 * Empty state shows a centered camera icon + hint copy.
 *
 * @param photos server-supplied photo list. First 8 thumbnails
 *   render in the 4-up grid; an `+N more` cell is added when there
 *   are more.
 * @param serverUrl base URL prefixed onto relative photo paths so
 *   `AsyncImage` can resolve them.
 * @param onOpenPhoto fires with the photo id when a cell is tapped.
 * @param onAddPhoto fires when the `+ Add` pill is tapped — null
 *   hides the pill (e.g. when the host hasn't wired the gallery
 *   destination).
 */
@Composable
internal fun PhotosCard(
    photos: List<TicketPhoto>,
    serverUrl: String,
    onOpenPhoto: ((photoId: Long) -> Unit)? = null,
    onAddPhoto: (() -> Unit)? = null,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp)) {
            // Header: section label + Add pill.
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Photos",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (onAddPhoto != null) {
                    Surface(
                        color = MaterialTheme.colorScheme.primaryContainer,
                        contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
                        shape = RoundedCornerShape(999.dp),
                        onClick = onAddPhoto,
                        modifier = Modifier.semantics { contentDescription = "Add photos to this ticket" },
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Icon(
                                Icons.Default.PhotoCamera,
                                contentDescription = null,
                                modifier = Modifier.size(14.dp),
                            )
                            Text(
                                "Add",
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.Medium,
                            )
                        }
                    }
                }
            }

            if (photos.isEmpty()) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp)
                        .aspectRatio(4f),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.PhotoCamera,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(28.dp),
                        )
                        Text(
                            "No photos yet — tap Add to attach repair images",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
                return@Card
            }

            // 4-up grid via two Rows (avoids LazyVerticalGrid measurement
            // weirdness inside another LazyColumn parent).
            val visible = photos.take(8)
            val overflow = (photos.size - visible.size).coerceAtLeast(0)
            val rows = visible.chunked(4)
            Column(
                modifier = Modifier.padding(top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                rows.forEachIndexed { rowIdx, rowPhotos ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        rowPhotos.forEach { photo ->
                            PhotoCell(
                                photo = photo,
                                serverUrl = serverUrl,
                                onClick = onOpenPhoto?.let { cb -> { cb(photo.id) } },
                                modifier = Modifier.weight(1f),
                            )
                        }
                        // Pad short rows with blank weight slots so cells stay
                        // square + aligned with the row above.
                        repeat(4 - rowPhotos.size) {
                            if (rowIdx == rows.lastIndex && overflow > 0 && it == 0) {
                                OverflowCell(
                                    overflow = overflow,
                                    modifier = Modifier.weight(1f),
                                )
                            } else {
                                Box(modifier = Modifier.weight(1f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PhotoCell(
    photo: TicketPhoto,
    serverUrl: String,
    onClick: (() -> Unit)?,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val url = remember(photo.url, serverUrl) {
        val raw = photo.url ?: return@remember null
        if (raw.startsWith("http")) raw else "$serverUrl$raw"
    }
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(8.dp),
        modifier = modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(8.dp))
            .let { if (onClick != null) it else it },
    ) {
        if (url == null) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Default.PhotoCamera,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(20.dp),
                )
            }
        } else {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(url)
                    .crossfade(true)
                    .build(),
                contentDescription = "Ticket photo ${photo.id}",
                modifier = Modifier
                    .fillMaxSize()
                    .let { if (onClick != null) it.semantics { contentDescription = "Tap to view photo ${photo.id}" } else it },
            )
        }
    }
}

@Composable
private fun OverflowCell(overflow: Int, modifier: Modifier) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(8.dp),
        modifier = modifier.aspectRatio(1f),
    ) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                "+$overflow",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// `remember` from compose runtime — alias to avoid the explicit import
// noise at the top while keeping the file under the project's preferred
// "explicit imports" convention. Kotlin compiler resolves @Composable
// remember from the inferred call-site composer scope.
@Composable
private fun <T> remember(key1: Any?, key2: Any?, calculation: () -> T): T =
    androidx.compose.runtime.remember(key1, key2) { calculation() }
