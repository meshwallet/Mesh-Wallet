package com.mesh.wallet.ui.components

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
fun Modifier.meshBalancePrivacyBlur(
    isHidden: Boolean,
    visibleOpacity: Float = 1f,
    hiddenOpacity: Float = 0.4f,
    blurRadius: Dp = 4.dp
): Modifier {
    val blur by animateDpAsState(
        targetValue = if (isHidden) blurRadius else 0.dp,
        animationSpec = tween(280),
        label = "balanceBlur"
    )
    val alpha by animateFloatAsState(
        targetValue = if (isHidden) hiddenOpacity else visibleOpacity,
        animationSpec = tween(280),
        label = "balanceAlpha"
    )
    return this.blur(blur).alpha(alpha)
}
