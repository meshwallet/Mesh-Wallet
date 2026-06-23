package com.mesh.wallet.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n

@Composable
fun MeshPasscodeBrandMark(
    modifier: Modifier = Modifier,
    height: Dp = 40.dp
) {
    val context = LocalContext.current
    Image(
        painter = painterResource(R.drawable.icon_png),
        contentDescription = L10n.tr(context, "welcome_brand"),
        modifier = modifier
            .fillMaxWidth()
            .height(height),
        contentScale = ContentScale.Fit
    )
}

@Composable
fun MeshPasscodeEntryLayout(
    modifier: Modifier = Modifier,
    header: @Composable (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .statusBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        header?.invoke()
        MeshPasscodeBrandMark(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = if (header != null) 12.dp else 0.dp, bottom = 4.dp),
            height = 40.dp
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            content = content
        )
    }
}
