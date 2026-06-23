package com.mesh.wallet.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography
import kotlin.math.roundToInt

@Composable
fun MeshSlideToSend(
    title: String,
    enabled: Boolean = true,
    onConfirmed: () -> Unit,
    modifier: Modifier = Modifier
) {
    var dragX by remember { mutableFloatStateOf(0f) }
    var trackWidth by remember { mutableFloatStateOf(0f) }
    var completed by remember { mutableStateOf(false) }
    val thumbSize = 48.dp
    val thumbPx = with(LocalDensity.current) { thumbSize.toPx() }
    val maxDrag = (trackWidth - thumbPx - 16f).coerceAtLeast(0f)
    val progress by animateFloatAsState(if (completed) 1f else if (maxDrag > 0) dragX / maxDrag else 0f)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(MeshMetrics.ButtonHeight)
            .clip(RoundedCornerShape(MeshMetrics.ButtonRadius))
            .background(MeshColors.FieldFill)
            .onSizeChanged { trackWidth = it.width.toFloat() }
            .pointerInput(enabled, maxDrag) {
                if (!enabled || completed) return@pointerInput
                detectHorizontalDragGestures(
                    onDragEnd = {
                        if (dragX >= maxDrag * 0.85f) {
                            completed = true
                            dragX = maxDrag
                            onConfirmed()
                        } else {
                            dragX = 0f
                        }
                    },
                    onHorizontalDrag = { _, amount ->
                        dragX = (dragX + amount).coerceIn(0f, maxDrag)
                    }
                )
            },
        contentAlignment = Alignment.CenterStart
    ) {
        Text(
            text = title,
            style = MeshTypography.Button,
            color = MeshColors.TextSecondary.copy(alpha = 1f - progress * 0.6f),
            modifier = Modifier.align(Alignment.Center)
        )
        Box(
            modifier = Modifier
                .padding(4.dp)
                .offset { IntOffset(dragX.roundToInt(), 0) }
                .height(thumbSize)
                .clip(CircleShape)
                .background(if (enabled) MeshColors.Accent else MeshColors.Accent.copy(alpha = 0.35f))
                .padding(12.dp),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.AutoMirrored.Filled.ArrowForward, contentDescription = null, tint = Color.White)
        }
    }
}
