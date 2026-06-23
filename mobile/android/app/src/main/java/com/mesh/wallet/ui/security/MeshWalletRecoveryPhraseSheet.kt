package com.mesh.wallet.ui.security

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.ui.components.MeshCloseButton
import com.mesh.wallet.ui.components.MeshSeedPhrasePanel
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MeshWalletRecoveryPhraseSheet(
    visible: Boolean,
    words: List<String>,
    walletName: String? = null,
    onDismiss: () -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(visible) {
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MeshColors.Background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(MeshMetrics.ScreenPadding)
        ) {
            MeshCloseButton(onClick = onDismiss)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                L10n.tr(context, "onboarding_recovery_title"),
                style = MeshTypography.ScreenTitle,
                color = MeshColors.TextPrimary
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                buildString {
                    walletName?.let { append("$it · ") }
                    append(L10n.tr(context, "onboarding_recovery_subtitle"))
                },
                style = MeshTypography.Secondary,
                color = MeshColors.TextSecondary
            )
            Spacer(modifier = Modifier.height(20.dp))
            MeshSeedPhrasePanel(
                words = words,
                footnote = L10n.tr(context, "onboarding_recovery_never_share"),
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}
