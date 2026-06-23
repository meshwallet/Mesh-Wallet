package com.mesh.wallet.ui.theme

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

object MeshWalletHomeColors {
    val topPurple = Color(0xFF9688AD)
    val bottomSurface = Color(0xFF0D0C14)
    val filterPillSelected = Color(0xFFA89BB5)

    val heroScrollFade: Brush = Brush.verticalGradient(
        colors = listOf(
            topPurple,
            Color(0xFF7A6E92),
            Color(0xFF4A4458),
            bottomSurface
        )
    )

    val sheetGradient: Brush = Brush.verticalGradient(
        colors = listOf(topPurple.copy(alpha = 0.35f), Color.Black)
    )
}

object MeshWalletHomeGlass {
    val discGlassTint = Color.White.copy(alpha = 0.07f)
    val chromeDiscGlassTint = Color.Black.copy(alpha = 0.52f)
    val fundFill = Color(0xFF7A6AB8).copy(alpha = 0.52f)
    val fundGlow = MeshColors.Accent.copy(alpha = 0.22f)
}
