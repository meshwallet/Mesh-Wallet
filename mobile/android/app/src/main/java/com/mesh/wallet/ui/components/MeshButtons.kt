package com.mesh.wallet.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun MeshPrimaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .height(MeshMetrics.ButtonHeight),
        shape = RoundedCornerShape(MeshMetrics.ButtonRadius),
        colors = ButtonDefaults.buttonColors(
            containerColor = MeshColors.Accent,
            contentColor = Color.White,
            disabledContainerColor = MeshColors.Accent.copy(alpha = 0.35f),
            disabledContentColor = Color.White.copy(alpha = 0.6f)
        )
    ) {
        Text(text = title, style = MeshTypography.Button, textAlign = TextAlign.Center)
    }
}

@Composable
fun MeshSecondaryButton(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .fillMaxWidth()
            .height(MeshMetrics.ButtonHeight),
        shape = RoundedCornerShape(MeshMetrics.ButtonRadius),
        border = BorderStroke(1.dp, MeshColors.Border),
        colors = ButtonDefaults.outlinedButtonColors(
            contentColor = Color.White,
            disabledContentColor = Color.White.copy(alpha = 0.35f)
        )
    ) {
        Text(text = title, style = MeshTypography.Button, textAlign = TextAlign.Center)
    }
}
