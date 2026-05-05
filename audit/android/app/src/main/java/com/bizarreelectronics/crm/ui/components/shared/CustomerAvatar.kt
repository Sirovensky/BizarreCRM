package com.bizarreelectronics.crm.ui.components.shared

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * CustomerAvatar — initial-circle avatar shared between customer list
 * and customer detail screens.
 *
 * CROSS49: the list row already rendered a 36dp `primaryContainer` circle
 * with the customer's first initial, but the detail screen had no avatar
 * at all. Extracting the composable here (parameterised on `size`) lets
 * both surfaces share one implementation — 36dp for rows, 72dp for detail.
 *
 * Colors follow the brand palette set by Theme.kt (orange-primary per
 * CROSS19): `primaryContainer` background + `onPrimaryContainer` foreground.
 *
 * §26.1 — [contentDesc] overrides the TalkBack announcement for this avatar.
 * Callers that embed the avatar inside a [BrandListItem] (which already uses
 * `mergeDescendants = true` + `Role.Button`) should pass `null` so the avatar
 * text is silently merged into the row's label. Standalone avatars (customer
 * detail header) should pass a human-readable label, e.g. "Customer avatar: Jane".
 */
@Composable
fun CustomerAvatar(
    name: String,
    modifier: Modifier = Modifier,
    size: Dp = 36.dp,
    textStyle: TextStyle = MaterialTheme.typography.labelLarge,
    contentDesc: String? = null,
) {
    val initial = name.firstOrNull { it.isLetter() }?.uppercaseChar()?.toString() ?: "?"
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primaryContainer)
            .then(
                if (contentDesc != null) {
                    // §26.1 — standalone avatar announces itself to TalkBack.
                    Modifier.semantics { contentDescription = contentDesc }
                } else {
                    // §26.1 — inside a mergeDescendants parent the avatar is
                    // decorative; suppress individual node to avoid double-reading.
                    Modifier.semantics { contentDescription = "" }
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = initial,
            style = textStyle,
            color = MaterialTheme.colorScheme.onPrimaryContainer,
        )
    }
}
