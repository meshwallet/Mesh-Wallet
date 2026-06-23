package com.mesh.wallet.ui.components

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun MeshFlowScreenHeader(
    title: String,
    onClose: () -> Unit,
    trailingText: String? = null,
    usesBackButton: Boolean = false,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(top = 4.dp, bottom = 8.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = MeshMetrics.ScreenPadding - 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (usesBackButton) {
                MeshBackButton(onClick = onClose)
            } else {
                MeshCloseButton(onClick = onClose)
            }
            Spacer(modifier = Modifier.weight(1f))
            trailingText?.let {
                Text(
                    text = it,
                    style = MeshTypography.Caption,
                    color = MeshColors.TextSecondary,
                    textAlign = TextAlign.End
                )
            }
        }
        Text(
            text = title,
            style = MeshTypography.ScreenTitle,
            color = MeshColors.TextPrimary,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = MeshMetrics.ScreenPadding)
                .padding(top = 12.dp)
        )
    }
}
