package com.mesh.wallet.ui.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.mesh.wallet.ui.theme.MeshColors
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

enum class PresentationEdge { Leading, Trailing }

@Composable
fun MeshEdgeDismissWrapper(
    visible: Boolean,
    onDismiss: () -> Unit,
    presentationEdge: PresentationEdge = PresentationEdge.Trailing,
    dismissEnabled: Boolean = true,
    content: @Composable () -> Unit
) {
    if (!visible) return

    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val screenWidth = with(density) { LocalConfiguration.current.screenWidthDp.dp.toPx() }
    val offsetX = remember { Animatable(if (presentationEdge == PresentationEdge.Trailing) screenWidth else -screenWidth) }

    androidx.compose.runtime.LaunchedEffect(Unit) {
        offsetX.animateTo(
            0f,
            spring(stiffness = Spring.StiffnessMediumLow, dampingRatio = 0.9f)
        )
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .offset { IntOffset(offsetX.value.roundToInt(), 0) }
            .then(
                if (dismissEnabled) {
                    Modifier.pointerInput(presentationEdge) {
                        detectHorizontalDragGestures(
                            onDragEnd = {
                                val threshold = screenWidth * 0.33f
                                val velocityDismiss = kotlin.math.abs(offsetX.value) > threshold
                                if (velocityDismiss) {
                                    scope.launch {
                                        offsetX.animateTo(
                                            if (presentationEdge == PresentationEdge.Trailing) screenWidth else -screenWidth
                                        )
                                        onDismiss()
                                    }
                                } else {
                                    scope.launch {
                                        offsetX.animateTo(0f, spring(dampingRatio = 0.9f))
                                    }
                                }
                            },
                            onHorizontalDrag = { _, dragAmount ->
                                scope.launch {
                                    val delta = if (presentationEdge == PresentationEdge.Trailing) {
                                        (offsetX.value + dragAmount).coerceAtLeast(0f)
                                    } else {
                                        (offsetX.value + dragAmount).coerceAtMost(0f)
                                    }
                                    offsetX.snapTo(delta)
                                }
                            }
                        )
                    }
                } else Modifier
            )
    ) {
        content()
    }
}
