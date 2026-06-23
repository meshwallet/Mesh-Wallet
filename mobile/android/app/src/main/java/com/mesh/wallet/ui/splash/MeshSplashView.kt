package com.mesh.wallet.ui.splash

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.mesh.wallet.R
import com.mesh.wallet.ui.theme.MeshColors

private val SplashLogoWidth = 148.dp
private val SplashLogoHeight = 48.dp

@Composable
fun MeshSplashView() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background),
        contentAlignment = Alignment.Center
    ) {
        Image(
            painter = painterResource(R.drawable.icon_png),
            contentDescription = "Mesh",
            modifier = Modifier
                .width(SplashLogoWidth)
                .height(SplashLogoHeight),
            contentScale = ContentScale.Fit
        )
    }
}
