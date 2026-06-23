package com.mesh.wallet.ui.components

import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun MeshBackupConfirmRow(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    label: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(
                interactionSource = MutableInteractionSource(),
                indication = null,
                onClick = { onCheckedChange(!checked) }
            )
            .padding(vertical = 4.dp),
        verticalAlignment = Alignment.Top
    ) {
        Box(
            modifier = Modifier
                .padding(top = 2.dp)
                .size(20.dp)
                .border(
                    width = 1.5.dp,
                    color = if (checked) MeshColors.TextPrimary else MeshColors.Border,
                    shape = RoundedCornerShape(4.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            if (checked) {
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = null,
                    tint = MeshColors.TextPrimary,
                    modifier = Modifier.size(12.dp)
                )
            }
        }
        Text(
            text = label,
            style = MeshTypography.Secondary,
            color = MeshColors.TextPrimary,
            modifier = Modifier
                .padding(start = 14.dp)
                .weight(1f)
        )
    }
}
