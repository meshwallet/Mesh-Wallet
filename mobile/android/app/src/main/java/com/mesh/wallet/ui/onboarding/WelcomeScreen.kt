package com.mesh.wallet.ui.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.components.MeshSecondaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun WelcomeScreen(onCreate: () -> Unit, onRestore: () -> Unit) {
    val context = LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(horizontal = MeshMetrics.ScreenPadding),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Spacer(modifier = Modifier.height(12.dp))
        Image(
            painter = painterResource(R.drawable.welcome_hero),
            contentDescription = null,
            modifier = Modifier.fillMaxWidth().height(280.dp),
            contentScale = ContentScale.Fit
        )
        Spacer(modifier = Modifier.height(28.dp))
        Image(
            painter = painterResource(R.drawable.icon_png),
            contentDescription = L10n.tr(context, "welcome_brand"),
            modifier = Modifier.height(48.dp)
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = L10n.Welcome.tagline(context),
            style = MeshTypography.Secondary,
            color = MeshColors.TextSecondary,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.weight(1f))
        MeshSecondaryButton(title = L10n.Welcome.restore(context), onClick = onRestore)
        Spacer(modifier = Modifier.height(12.dp))
        MeshPrimaryButton(title = L10n.Welcome.create(context), onClick = onCreate)
        Spacer(modifier = Modifier.height(20.dp))
        Text(L10n.Welcome.legalPrefix(context), style = MeshTypography.Caption, color = MeshColors.TextTertiary, textAlign = TextAlign.Center)
        Spacer(modifier = Modifier.height(16.dp))
    }
}
