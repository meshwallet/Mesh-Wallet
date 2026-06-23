package com.mesh.wallet.ui.wallet

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.domain.model.WalletReceiveSlot
import com.mesh.wallet.ui.components.MeshAccountsDrawerGlass
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTypography
import java.text.DecimalFormat
import kotlin.math.roundToInt

private const val DRAWER_WIDTH_RATIO = 0.35f
private const val DRAWER_LEADING_INSET_DP = 12f

@Composable
fun WalletAddressDrawer(
    visible: Boolean,
    slots: List<WalletReceiveSlot>,
    focusedIndex: Int,
    canAdd: Boolean = true,
    walletTotal: String? = null,
    onDismiss: () -> Unit,
    onSelectSlot: (Int) -> Unit,
    onAddAddress: () -> Unit
) {
    if (!visible) return
    val context = LocalContext.current
    val screenWidthDp = LocalConfiguration.current.screenWidthDp.dp
    val density = LocalDensity.current

    val panelWidth = remember(screenWidthDp) {
        (screenWidthDp * DRAWER_WIDTH_RATIO).coerceIn(128.dp, 196.dp)
    }
    val horizontalPadding = remember(panelWidth) {
        maxOf(10.dp, panelWidth * 0.09f)
    }

    val targetOffsetPx = with(density) { DRAWER_LEADING_INSET_DP.dp.toPx() }
    val offsetX by animateFloatAsState(
        targetValue = targetOffsetPx,
        animationSpec = spring(dampingRatio = 0.86f, stiffness = 420f),
        label = "drawerSlide"
    )

    Box(modifier = Modifier.fillMaxSize()) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.45f))
                .clickable(onClick = onDismiss)
        )

        MeshAccountsDrawerGlass(
            modifier = Modifier
                .align(Alignment.TopStart)
                .statusBarsPadding()
                .padding(top = 16.dp)
                .offset { IntOffset(offsetX.roundToInt(), 0) }
                .width(panelWidth)
                .widthIn(max = panelWidth)
                .padding(4.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 10.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(44.dp)
                        .padding(horizontal = horizontalPadding - 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Image(
                        painter = painterResource(R.drawable.ic_subaccounts),
                        contentDescription = null,
                        modifier = Modifier.size(18.dp)
                    )
                    Text(
                        L10n.WalletAddressDrawer.title(context),
                        style = MeshTypography.Label,
                        color = MeshColors.TextSecondary,
                        modifier = Modifier.padding(start = 7.dp),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }

                walletTotal?.let { total ->
                    Text(
                        "${L10n.WalletAddressDrawer.totalLabel(context)}: $$total",
                        style = MeshTypography.Caption,
                        color = MeshColors.Accent,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = horizontalPadding, vertical = 4.dp),
                        textAlign = TextAlign.Center
                    )
                }

                Column(
                    modifier = Modifier.padding(horizontal = maxOf(4.dp, horizontalPadding - 6.dp))
                ) {
                    slots.forEach { slot ->
                        DrawerSlotRow(
                            slot = slot,
                            selected = slot.index == focusedIndex,
                            onClick = {
                                onSelectSlot(slot.index)
                                onDismiss()
                            }
                        )
                    }
                    if (canAdd) {
                        AddSlotRow(onClick = onAddAddress)
                    }
                }

                Text(
                    L10n.WalletAddressDrawer.subtitle(context),
                    style = MeshTypography.Caption.copy(fontSize = 9.sp),
                    color = MeshColors.TextTertiary.copy(alpha = 0.8f),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = horizontalPadding)
                        .padding(top = 10.dp),
                    maxLines = 2
                )
            }
        }
    }
}

@Composable
private fun DrawerSlotRow(slot: WalletReceiveSlot, selected: Boolean, onClick: () -> Unit) {
    val context = LocalContext.current
    val balance = slot.balanceUsdt?.let { DecimalFormat("#,##0.00").format(it) + " USDT" } ?: "…"

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .background(
                if (selected) MeshColors.FieldFill else MeshColors.FieldFill.copy(alpha = 0.55f),
                RoundedCornerShape(10.dp)
            )
            .border(
                1.dp,
                if (selected) MeshColors.Accent.copy(alpha = 0.55f) else MeshColors.BorderSubtle.copy(alpha = 0.7f),
                RoundedCornerShape(10.dp)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 8.dp)
    ) {
        if (slot.index == 0) {
            Text(
                L10n.WalletAddressDrawer.mainBadge(context),
                style = MeshTypography.Caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
                color = MeshColors.TextPrimary,
                modifier = Modifier
                    .background(MeshColors.SurfacePressed.copy(alpha = 0.7f), RoundedCornerShape(50))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            )
        } else {
            Text(
                slot.name,
                style = MeshTypography.Caption,
                color = if (selected) MeshColors.TextPrimary else MeshColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
        Text(
            balance,
            style = MeshTypography.Caption.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold),
            color = if (selected) MeshColors.TextPrimary else MeshColors.TextSecondary,
            maxLines = 1
        )
    }
}

@Composable
private fun AddSlotRow(onClick: () -> Unit) {
    val context = LocalContext.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .border(1.dp, MeshColors.BorderSubtle.copy(alpha = 0.7f), RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 10.dp, vertical = 16.dp),
        contentAlignment = Alignment.Center
    ) {
        Icon(
            Icons.Default.Add,
            contentDescription = L10n.WalletAddressDrawer.createAccount(context),
            tint = MeshColors.TextTertiary
        )
    }
}
