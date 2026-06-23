package com.mesh.wallet.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics

@Composable
fun MeshChromeButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .size(MeshMetrics.ChromeButtonSize)
            .clip(CircleShape)
            .background(MeshColors.ChromeFill)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = MeshColors.TextPrimary
        )
    }
}

@Composable
fun MeshBackButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    MeshChromeButton(
        icon = Icons.AutoMirrored.Filled.ArrowBack,
        contentDescription = "Back",
        onClick = onClick,
        modifier = modifier
    )
}

@Composable
fun MeshCloseButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    MeshChromeButton(
        icon = Icons.Default.Close,
        contentDescription = "Close",
        onClick = onClick,
        modifier = modifier
    )
}
