package com.mesh.wallet.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun MeshSendFieldButton(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        onClick = onClick,
        modifier = modifier.height(34.dp),
        shape = RoundedCornerShape(50),
        color = MeshColors.FieldFill.copy(alpha = 0.55f),
        border = BorderStroke(1.dp, MeshColors.BorderSubtle)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(imageVector = icon, contentDescription = null, tint = MeshColors.TextSecondary, modifier = Modifier.padding(end = 6.dp))
            Text(title, style = MeshTypography.Label, color = MeshColors.TextSecondary, maxLines = 1)
        }
    }
}
