package com.mesh.wallet.ui.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.ui.components.MeshCloseButton
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeedPhraseSecuritySheet(
    visible: Boolean,
    onDismiss: () -> Unit,
    onContinue: () -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var checked by remember { mutableStateOf(setOf<Int>()) }
    val items = listOf(
        L10n.tr(context, "onboarding_seed_security_item_1"),
        L10n.tr(context, "onboarding_seed_security_item_2"),
        L10n.tr(context, "onboarding_seed_security_item_3")
    )

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
            Spacer(modifier = Modifier.height(8.dp))
            Image(
                painter = painterResource(R.drawable.secret_phrase_security_hero),
                contentDescription = null,
                modifier = Modifier
                    .size(200.dp)
                    .align(Alignment.CenterHorizontally)
            )
            Spacer(modifier = Modifier.height(24.dp))
            Text(
                L10n.tr(context, "onboarding_seed_security_title"),
                style = MeshTypography.ScreenTitle,
                color = MeshColors.TextPrimary,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(20.dp))
            items.forEachIndexed { index, text ->
                SecurityCheckRow(
                    text = text,
                    checked = checked.contains(index),
                    onToggle = {
                        checked = if (checked.contains(index)) checked - index else checked + index
                    }
                )
                Spacer(modifier = Modifier.height(12.dp))
            }
            Spacer(modifier = Modifier.height(24.dp))
            MeshPrimaryButton(
                title = L10n.tr(context, "onboarding_continue"),
                onClick = {
                    onDismiss()
                    onContinue()
                },
                enabled = checked.size == items.size
            )
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun SecurityCheckRow(text: String, checked: Boolean, onToggle: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MeshColors.FieldFill, RoundedCornerShape(MeshMetrics.CardRadius))
            .clickable(onClick = onToggle)
            .padding(16.dp),
        verticalAlignment = Alignment.Top
    ) {
        Icon(
            imageVector = if (checked) Icons.Filled.CheckCircle else Icons.Outlined.Circle,
            contentDescription = null,
            tint = if (checked) MeshColors.Success else MeshColors.TextTertiary,
            modifier = Modifier.size(22.dp)
        )
        Text(
            text = text,
            style = MeshTypography.Secondary,
            color = MeshColors.TextPrimary,
            modifier = Modifier
                .weight(1f)
                .padding(start = 14.dp)
        )
    }
}
