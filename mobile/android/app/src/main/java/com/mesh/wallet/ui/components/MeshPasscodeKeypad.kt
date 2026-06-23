package com.mesh.wallet.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

private sealed class KeypadKey {
    data class Digit(val value: Char) : KeypadKey()
    data object Delete : KeypadKey()
    data object Spacer : KeypadKey()
}

@Composable
fun MeshPasscodeDots(
    enteredCount: Int,
    total: Int = 6,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center
    ) {
        repeat(total) { index ->
            val filled = index < enteredCount
            Box(
                modifier = Modifier
                    .size(MeshMetrics.PasscodeDotSize)
                    .clip(CircleShape)
                    .background(if (filled) MeshColors.Accent else MeshColors.BorderSubtle)
            )
            if (index < total - 1) Spacer(modifier = Modifier.size(16.dp))
        }
    }
}

@Composable
fun MeshPasscodeKeypad(
    onDigit: (Char) -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier
) {
    val keys = listOf(
        listOf(KeypadKey.Digit('1'), KeypadKey.Digit('2'), KeypadKey.Digit('3')),
        listOf(KeypadKey.Digit('4'), KeypadKey.Digit('5'), KeypadKey.Digit('6')),
        listOf(KeypadKey.Digit('7'), KeypadKey.Digit('8'), KeypadKey.Digit('9')),
        listOf(KeypadKey.Spacer, KeypadKey.Digit('0'), KeypadKey.Delete)
    )

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        keys.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                row.forEach { key ->
                    when (key) {
                        KeypadKey.Spacer -> Spacer(modifier = Modifier.size(72.dp))
                        KeypadKey.Delete -> KeypadButton(onClick = onDelete) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Filled.Backspace,
                                contentDescription = "Delete",
                                tint = MeshColors.TextPrimary
                            )
                        }
                        is KeypadKey.Digit -> KeypadButton(onClick = { onDigit(key.value) }) {
                            Text(text = key.value.toString(), style = MeshTypography.ScreenTitle, color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun KeypadButton(
    onClick: () -> Unit,
    content: @Composable () -> Unit
) {
    Box(
        modifier = Modifier
            .size(72.dp)
            .clip(CircleShape)
            .background(MeshColors.ChromeFill)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        content()
    }
}
