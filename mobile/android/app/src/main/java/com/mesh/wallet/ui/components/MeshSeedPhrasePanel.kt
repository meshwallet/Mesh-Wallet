package com.mesh.wallet.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.MeshClipboard
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography
import kotlinx.coroutines.delay

@Composable
fun MeshSeedPhrasePanel(
    words: List<String>,
    modifier: Modifier = Modifier,
    footnote: String? = null,
    showsCopyAction: Boolean = true,
    onCopied: (() -> Unit)? = null
) {
    val context = LocalContext.current
    var didCopy by remember { mutableStateOf(false) }
    val phraseText = words.joinToString(" ")
    val columnSplit = (words.size + 1) / 2
    val resolvedFootnote = footnote ?: L10n.tr(context, "onboarding_recovery_subtitle")

    LaunchedEffect(didCopy) {
        if (!didCopy) return@LaunchedEffect
        delay(2_500)
        didCopy = false
    }

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MeshColors.FieldFill, RoundedCornerShape(MeshMetrics.CardRadius))
                .padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            SeedPhraseWordColumn(words, 0 until columnSplit, modifier = Modifier.weight(1f))
            SeedPhraseWordColumn(words, columnSplit until words.size, modifier = Modifier.weight(1f))
        }

        Spacer(modifier = Modifier.height(10.dp))
        Text(
            text = resolvedFootnote,
            style = MeshTypography.Caption,
            color = MeshColors.TextTertiary
        )

        if (showsCopyAction) {
            Spacer(modifier = Modifier.height(16.dp))
            MeshSecondaryButton(
                title = if (didCopy) {
                    L10n.Common.copied(context)
                } else {
                    L10n.tr(context, "onboarding_recovery_copy")
                },
                onClick = {
                    if (MeshClipboard.copyString(context, "recovery", phraseText)) {
                        didCopy = true
                        onCopied?.invoke()
                    }
                }
            )
            if (didCopy) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = L10n.tr(context, "onboarding_recovery_copied_warning"),
                    style = MeshTypography.Caption,
                    color = MeshColors.Success
                )
            }
        }
    }
}

@Composable
private fun SeedPhraseWordColumn(
    words: List<String>,
    indices: IntRange,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        indices.forEach { index ->
            Row(
                modifier = Modifier.padding(vertical = 7.dp),
                verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
            ) {
                Text(
                    text = "${index + 1}",
                    style = MeshTypography.Label,
                    color = MeshColors.TextTertiary,
                    modifier = Modifier.width(18.dp)
                )
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = words[index],
                    style = MeshTypography.Body,
                    color = MeshColors.TextPrimary
                )
            }
        }
    }
}
