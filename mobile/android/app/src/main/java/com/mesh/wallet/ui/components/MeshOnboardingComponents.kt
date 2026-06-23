package com.mesh.wallet.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun MeshOnboardingScreen(
    modifier: Modifier = Modifier,
    footer: @Composable () -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .statusBarsPadding()
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = MeshMetrics.ScreenPadding),
            content = content
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = MeshMetrics.ScreenPadding)
                .padding(bottom = 12.dp)
        ) {
            footer()
        }
    }
}

@Composable
fun MeshTitleBlock(
    title: String,
    subtitle: String? = null,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text(text = title, style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
        subtitle?.let {
            Text(
                text = it,
                style = MeshTypography.Secondary,
                color = MeshColors.TextSecondary,
                modifier = Modifier.padding(top = 8.dp)
            )
        }
    }
}

@Composable
fun MeshInputPanel(
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .background(MeshColors.FieldFill, RoundedCornerShape(MeshMetrics.FieldRadius))
            .padding(16.dp)
    ) {
        content()
    }
}

@Composable
fun MeshWalletNameField(
    name: String,
    onNameChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxWidth()) {
        Text("Wallet name", style = MeshTypography.Label, color = MeshColors.TextSecondary)
        MeshInputPanel(modifier = Modifier.padding(top = 10.dp)) {
            BasicTextField(
                value = name,
                onValueChange = onNameChange,
                textStyle = MeshTypography.Body.copy(color = MeshColors.TextPrimary),
                singleLine = true,
                cursorBrush = SolidColor(MeshColors.Accent),
                modifier = Modifier.fillMaxWidth(),
                decorationBox = { inner ->
                    if (name.isEmpty()) {
                        Text(placeholder, style = MeshTypography.Body, color = MeshColors.TextTertiary)
                    }
                    inner()
                }
            )
        }
        Text(
            text = "Optional. Shown in your wallet list.",
            style = MeshTypography.Caption,
            color = MeshColors.TextTertiary,
            modifier = Modifier.padding(top = 8.dp)
        )
    }
}

@Composable
fun MeshMultilineField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    minHeight: Dp = 140.dp,
    monospaced: Boolean = false
) {
    val textStyle = if (monospaced) {
        MeshTypography.Body.copy(fontFamily = FontFamily.Monospace, color = MeshColors.TextPrimary)
    } else {
        MeshTypography.Body.copy(color = MeshColors.TextPrimary)
    }
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        textStyle = textStyle,
        cursorBrush = SolidColor(MeshColors.Accent),
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = minHeight),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) {
                    Text(
                        text = placeholder,
                        style = textStyle.copy(color = MeshColors.TextTertiary)
                    )
                }
                inner()
            }
        }
    )
}

@Composable
fun meshOnboardingFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = MeshColors.Accent,
    unfocusedBorderColor = MeshColors.Border,
    focusedContainerColor = MeshColors.FieldFill,
    unfocusedContainerColor = MeshColors.FieldFill,
    focusedTextColor = MeshColors.TextPrimary,
    unfocusedTextColor = MeshColors.TextPrimary,
    cursorColor = MeshColors.Accent
)

@Composable
fun MeshRestoreFieldActions(
    onPaste: () -> Unit,
    onClear: () -> Unit,
    isPasting: Boolean,
    pasteLabel: String,
    clearLabel: String = "Clear",
    enabled: Boolean = true,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = pasteLabel,
            style = MeshTypography.Caption,
            color = if (enabled && !isPasting) MeshColors.TextSecondary else MeshColors.TextTertiary,
            modifier = Modifier.then(
                if (enabled && !isPasting) Modifier.clickableWithoutRipple(onPaste) else Modifier
            )
        )
        Text(
            text = clearLabel,
            style = MeshTypography.Caption,
            color = if (enabled) MeshColors.TextSecondary else MeshColors.TextTertiary,
            modifier = Modifier.then(
                if (enabled) Modifier.clickableWithoutRipple(onClear) else Modifier
            )
        )
    }
}

private fun Modifier.clickableWithoutRipple(onClick: () -> Unit): Modifier =
    clickable(
        interactionSource = MutableInteractionSource(),
        indication = null,
        onClick = onClick
    )
