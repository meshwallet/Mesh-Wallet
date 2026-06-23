package com.mesh.wallet.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors

@Composable
fun MeshAccountsDrawerGlass(
    modifier: Modifier = Modifier,
    cornerRadius: androidx.compose.ui.unit.Dp = 16.dp,
    content: @Composable BoxScope.() -> Unit
) {
    val shape = RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .shadow(
                elevation = 16.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.45f),
                spotColor = Color.Black.copy(alpha = 0.25f)
            )
            .clip(shape)
            .background(MeshColors.Surface, shape)
            .background(Color(0xFF141416), shape)
            .border(1.dp, MeshColors.Border.copy(alpha = 0.55f), shape),
        content = content
    )
}
