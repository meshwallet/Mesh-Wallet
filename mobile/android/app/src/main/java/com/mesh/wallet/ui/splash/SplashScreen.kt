package com.mesh.wallet.ui.splash

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun SplashScreen() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "Mesh",
            style = MeshTypography.Hero,
            color = MeshColors.Accent
        )
    }
}
