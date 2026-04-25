package com.bizarreelectronics.crm.ui.components.auth

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/**
 * Shared pill-shaped primary CTA used across all login-flow steps:
 * Connect (server step), Create Shop (register step), Sign In (credentials step),
 * Continue (2FA verify step).
 *
 * Spec:
 *  - 56dp fixed height
 *  - 28dp corner radius (pill)
 *  - fillMaxWidth (caller controls width via [modifier])
 *  - containerColor = colorScheme.primary (cream in dark theme)
 *  - contentColor = colorScheme.onPrimary
 *  - disabled: onSurface @ 0.24f container / 0.48f content
 *  - spinner (20dp, 2dp stroke) when [isLoading]; label (titleMedium semibold) otherwise
 *
 * LOGIN-MOCK-049
 */
@Composable
fun LoginPillButton(
    onClick: () -> Unit,
    enabled: Boolean,
    isLoading: Boolean,
    label: String,
    modifier: Modifier = Modifier,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp),
        shape = RoundedCornerShape(28.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.primary,
            contentColor = MaterialTheme.colorScheme.onPrimary,
            disabledContainerColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.24f),
            disabledContentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.48f),
        ),
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary,
            )
        } else {
            Text(
                text = label,
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
            )
        }
    }
}
