package com.bizarreelectronics.crm.util

import android.content.ClipData
import android.view.DragEvent
import android.view.View
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.draganddrop.dragAndDropSource
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.DragAndDropTransferData
import androidx.compose.ui.draganddrop.mimeTypes
import androidx.compose.ui.draganddrop.toAndroidDragEvent

/**
 * DragAndDropSupport -- Section 22 L2266-L2268 (plan:L2266)
 *
 * Compose Modifier extensions for inter-view and cross-app drag-and-drop.
 *
 * ### [Modifier.draggableItem]
 * Starts a system drag-and-drop operation on long-press with the given
 * [ClipData] payload. Uses DRAG_FLAG_GLOBAL so the data can be received
 * by other apps (e.g., dragging a customer name into a note editor).
 *
 * Supported payload MIME types for cross-app drops:
 * - text/plain  -- ticket IDs, customer names, phone numbers
 * - text/uri-list -- photo URLs, deep-link URIs
 * - image/STAR -- dragged photo thumbnails
 *
 * ### [Modifier.dropTarget]
 * Accepts drop events. [onDrop] receives the [ClipData] from the source.
 * Return true from [onDrop] to signal successful consumption.
 *
 * Where to consume:
 * - Ticket list rows: drag ticket ID into a "Merge with" drop zone
 * - Inventory list: drag part onto a ticket to attach it
 * - Photo gallery: drag image onto customer record
 * - SMS compose field accepts text/URI drops from other apps (cross-app)
 *
 * ChromeOS note:
 * ChromeOS routes cross-window drags through the same DragEvent mechanism.
 * DRAG_FLAG_GLOBAL is required for cross-window drops on ChromeOS.
 */

/**
 * Attaches a long-press-initiated drag gesture that starts a system
 * drag-and-drop with [clipData] as the payload.
 *
 * @param clipData ClipData to transfer. Caller sets the correct MIME type.
 * @param flags    Drag flags. Defaults to DRAG_FLAG_GLOBAL for cross-app
 *                 transfers. Pass 0 to restrict to the same app.
 */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.draggableItem(
    clipData: ClipData,
    flags: Int = View.DRAG_FLAG_GLOBAL,
): Modifier = this.dragAndDropSource(
    drawDragDecoration = {},
    // Named `block` arg disambiguates from the new `transferData`
    // overload introduced in compose-foundation 1.8 / material3 1.4.
    block = {
        detectTapGestures(
            onLongPress = {
                startTransfer(
                    DragAndDropTransferData(
                        clipData = clipData,
                        flags = flags,
                    ),
                )
            },
        )
    },
)

/**
 * Marks this composable as a drop target. [onDrop] is called when a
 * drag-and-drop operation ends over this composable.
 *
 * @param acceptedMimeTypes MIME types to accept. Empty list accepts all types.
 * @param onDrop            Called with the dropped [ClipData]. Return true
 *                          if the drop was consumed, false to reject.
 */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.dropTarget(
    acceptedMimeTypes: List<String> = emptyList(),
    onDrop: (ClipData) -> Boolean,
): Modifier = composed {
    val target = remember {
        object : DragAndDropTarget {
            override fun onDrop(event: DragAndDropEvent): Boolean {
                val androidEvent: DragEvent = event.toAndroidDragEvent()
                val clip = androidEvent.clipData ?: return false

                if (acceptedMimeTypes.isNotEmpty()) {
                    val offered = event.mimeTypes()
                    val accepted = offered.any { mime ->
                        acceptedMimeTypes.any { wanted ->
                            wanted == mime || (wanted.endsWith("/*") &&
                                mime.startsWith(wanted.removeSuffix("*")))
                        }
                    }
                    if (!accepted) return false
                }

                return onDrop(clip)
            }
        }
    }

    this.dragAndDropTarget(
        shouldStartDragAndDrop = { event ->
            if (acceptedMimeTypes.isEmpty()) {
                true
            } else {
                val offered = event.mimeTypes()
                offered.any { mime ->
                    acceptedMimeTypes.any { wanted ->
                        wanted == mime || (wanted.endsWith("/*") &&
                            mime.startsWith(wanted.removeSuffix("*")))
                    }
                }
            }
        },
        target = target,
    )
}

/** Build a plain-text [ClipData] for dragging a label+value string. */
fun textClipData(label: String, text: String): ClipData =
    ClipData.newPlainText(label, text)

/** Build a URI [ClipData] for dragging a deep-link or photo URL. */
fun uriClipData(label: String, uriString: String): ClipData =
    ClipData.newRawUri(label, android.net.Uri.parse(uriString))

