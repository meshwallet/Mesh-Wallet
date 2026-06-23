package com.mesh.wallet.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.domain.model.WalletReceiveSlot
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography
import java.text.DecimalFormat

@Composable
fun MeshWalletSlotPicker(
    headerTitle: String,
    slots: List<WalletReceiveSlot>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    var expanded by remember { mutableStateOf(false) }
    val selected = slots.firstOrNull { it.index == selectedIndex } ?: slots.firstOrNull()

    Column(modifier = modifier) {
        Text(
            headerTitle,
            style = MeshTypography.Caption,
            color = MeshColors.TextSecondary,
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(bottom = 8.dp)
        )
        SlotRow(
            slot = selected,
            selected = true,
            onClick = { expanded = !expanded },
            trailing = {
                Icon(
                    if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                    contentDescription = null,
                    tint = MeshColors.TextSecondary
                )
            }
        )
        AnimatedVisibility(visible = expanded, enter = expandVertically(), exit = shrinkVertically()) {
            Column {
                slots.filter { it.index != selectedIndex }.forEach { slot ->
                    SlotRow(slot = slot, selected = false, onClick = {
                        onSelect(slot.index)
                        expanded = false
                    })
                }
            }
        }
    }
}

@Composable
private fun SlotRow(
    slot: WalletReceiveSlot?,
    selected: Boolean,
    onClick: () -> Unit,
    trailing: @Composable (() -> Unit)? = null
) {
    if (slot == null) return
    val context = LocalContext.current
    val balance = slot.balanceUsdt?.let {
        DecimalFormat("#,##0.00").format(it) + " USDT"
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .background(
                if (selected) MeshColors.Accent.copy(alpha = 0.12f) else MeshColors.ListCardFill,
                RoundedCornerShape(MeshMetrics.CardRadius)
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(slot.name, style = MeshTypography.Body, color = MeshColors.TextPrimary)
                if (slot.index == 0) {
                    Text(
                        "  ${L10n.tr(context, "wallet_address_drawer_main_badge")}",
                        style = MeshTypography.Caption,
                        color = MeshColors.Accent
                    )
                }
            }
            Text(
                slot.address.take(8) + "…" + slot.address.takeLast(6),
                style = MeshTypography.Caption,
                color = MeshColors.TextSecondary
            )
            balance?.let {
                Text(it, style = MeshTypography.Caption, color = MeshColors.Accent)
            }
        }
        trailing?.invoke()
    }
}
