package com.mesh.wallet.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.SouthWest
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTypography
import com.mesh.wallet.ui.theme.MeshWalletHomeGlass

@Composable
fun MeshWalletCircleActionButton(
    title: String,
    onClick: () -> Unit,
    isReceive: Boolean = title.contains("ceive", ignoreCase = true)
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        androidx.compose.foundation.layout.Box(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(MeshWalletHomeGlass.discGlassTint)
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (isReceive) Icons.Filled.SouthWest else Icons.Filled.NorthEast,
                contentDescription = title,
                tint = MeshColors.HomeTextPrimary,
                modifier = Modifier.size(22.dp)
            )
        }
        Text(
            text = title,
            style = MeshTypography.Caption,
            color = MeshColors.HomeTextSecondary,
            modifier = Modifier.align(Alignment.CenterHorizontally)
        )
    }
}
