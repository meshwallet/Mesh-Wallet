package com.mesh.wallet.ui.components

import android.media.MediaPlayer
import android.net.Uri
import android.widget.FrameLayout
import android.widget.VideoView
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.mesh.wallet.R

@Composable
fun MeshBundleVideoPlayer(
    modifier: Modifier = Modifier,
    loops: Boolean = true,
    onReady: () -> Unit = {}
) {
    val context = LocalContext.current
    var ready by remember { mutableStateOf(false) }
    val opacity by animateFloatAsState(
        targetValue = if (ready) 1f else 0f,
        animationSpec = tween(durationMillis = 750),
        label = "videoFade"
    )

    AndroidView(
        factory = { ctx ->
            FrameLayout(ctx).apply {
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                val videoView = VideoView(ctx).apply {
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                    val uri = Uri.parse("android.resource://${ctx.packageName}/${R.raw.wallet}")
                    setVideoURI(uri)
                    setOnPreparedListener { mp ->
                        mp.isLooping = loops
                        mp.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING)
                        start()
                        ready = true
                        onReady()
                    }
                }
                addView(videoView)
            }
        },
        modifier = modifier.alpha(opacity)
    )
}
