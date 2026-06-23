package com.mesh.wallet.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.mesh.wallet.R
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

object MeshColors {
    val Background = Color(0xFF000000)
    val BackgroundElevated = Color(0xFF141414)
    val Surface = Color(0xFF1C1C1E)
    val SurfaceElevated = Color(0xFF2C2C2E)
    val SurfacePressed = Color(0xFF3A3A3C)
    val Accent = Color(0xFFA18DCA)
    val AccentPressed = Color(0xFF8B76B3)
    val AccentMuted = Color(0xFFA18DCA).copy(alpha = 0.35f)
    val FieldFill = Color(0xFF1A1A1E)
    val ListCardFill = Color(0xFF1A1A1A)
    val Success = Color(0xFF34C759)
    val Warning = Color(0xFFFF9F0A)
    val TextPrimary = Color.White
    val TextSecondary = Color.White.copy(alpha = 0.55f)
    val TextTertiary = Color.White.copy(alpha = 0.35f)
    val HomeTextPrimary = Color.White.copy(alpha = 0.82f)
    val HomeTextSecondary = Color.White.copy(alpha = 0.48f)
    val Border = Color.White.copy(alpha = 0.12f)
    val BorderSubtle = Color.White.copy(alpha = 0.08f)
    val ChromeFill = Color.White.copy(alpha = 0.06f)
    val HomeCircleButtonFill = Color.White.copy(alpha = 0.08f)
    val HomeCircleButtonStroke = Color.White.copy(alpha = 0.14f)
}

object MeshMetrics {
    val ScreenPadding = 24.dp
    val CardRadius = 16.dp
    val ButtonRadius = 28.dp
    val ButtonHeight = 56.dp
    val ChromeButtonSize = 48.dp
    val FieldRadius = 14.dp
    val SectionSpacing = 24.dp
    val WalletCardRadius = 24.dp
    val PasscodeDotSize = 11.dp
}

object MeshTypography {
    private val GeistRegular = Font(R.font.geist_regular, FontWeight.Normal)
    private val GeistMedium = Font(R.font.geist_medium, FontWeight.Medium)
    private val GeistSemiBold = Font(R.font.geist_semibold, FontWeight.SemiBold)
    private val GeistBold = Font(R.font.geist_bold, FontWeight.Bold)

    val Sans = FontFamily(GeistRegular, GeistMedium, GeistSemiBold, GeistBold)

    val Hero = TextStyle(fontFamily = Sans, fontSize = 36.sp, fontWeight = FontWeight.Light)
    val ScreenTitle = TextStyle(fontFamily = Sans, fontSize = 32.sp, fontWeight = FontWeight.SemiBold)
    val SectionTitle = TextStyle(fontFamily = Sans, fontSize = 19.sp, fontWeight = FontWeight.Normal)
    val Button = TextStyle(fontFamily = Sans, fontSize = 18.sp, fontWeight = FontWeight.Medium)
    val Body = TextStyle(fontFamily = Sans, fontSize = 17.sp, fontWeight = FontWeight.Normal)
    val Secondary = TextStyle(fontFamily = Sans, fontSize = 16.sp, fontWeight = FontWeight.Light)
    val Caption = TextStyle(fontFamily = Sans, fontSize = 14.sp, fontWeight = FontWeight.Light)
    val Label = TextStyle(fontFamily = Sans, fontSize = 13.sp, fontWeight = FontWeight.Light)
    val BalanceHero = TextStyle(fontFamily = Sans, fontSize = 48.sp, fontWeight = FontWeight.SemiBold)
    val BalanceCollapsed = TextStyle(fontFamily = Sans, fontSize = 22.sp, fontWeight = FontWeight.Light)
}

private val DarkColorScheme = darkColorScheme(
    primary = MeshColors.Accent,
    onPrimary = Color.White,
    background = MeshColors.Background,
    onBackground = MeshColors.TextPrimary,
    surface = MeshColors.Surface,
    onSurface = MeshColors.TextPrimary,
    error = Color(0xFF5C2D2D),
    onError = Color.White
)

@Composable
fun MeshTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
