package com.mesh.wallet.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.domain.model.TransactionDirection
import com.mesh.wallet.domain.model.WalletTransaction
import com.mesh.wallet.ui.components.meshBalancePrivacyBlur
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTypography
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

data class WalletTransactionDayGroup(
    val day: String,
    val items: List<WalletTransaction>
)

fun List<WalletTransaction>.groupedByDay(context: android.content.Context): List<WalletTransactionDayGroup> {
    val order = mutableListOf<String>()
    val buckets = linkedMapOf<String, MutableList<WalletTransaction>>()
    for (tx in this) {
        val label = activitySectionDateLabel(context, tx.timestamp)
        if (!buckets.containsKey(label)) {
            order.add(label)
            buckets[label] = mutableListOf()
        }
        buckets.getValue(label).add(tx)
    }
    return order.map { WalletTransactionDayGroup(it, buckets.getValue(it)) }
}

fun activitySectionDateLabel(context: android.content.Context, timestamp: Long): String {
    val now = Calendar.getInstance()
    val date = Calendar.getInstance().apply { timeInMillis = timestamp }
    if (isSameDay(now, date)) return L10n.tr(context, "wallet_today")

    val yesterday = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
    if (isSameDay(yesterday, date)) return "Yesterday"

    val includesYear = date.get(Calendar.YEAR) != now.get(Calendar.YEAR)
    val pattern = if (includesYear) "d MMMM yyyy" else "d MMMM"
    val formatter = SimpleDateFormat(pattern, Locale.getDefault())
    return titleStyleDate(formatter.format(Date(timestamp)))
}

private fun isSameDay(first: Calendar, second: Calendar): Boolean {
    return first.get(Calendar.YEAR) == second.get(Calendar.YEAR) &&
        first.get(Calendar.DAY_OF_YEAR) == second.get(Calendar.DAY_OF_YEAR)
}

private fun titleStyleDate(raw: String): String {
    return raw
        .split(" ")
        .filter { it.isNotBlank() }
        .joinToString(" ") { part ->
            part.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
        }
}

@Composable
fun WalletActivitySectionHeader(
    title: String,
    modifier: Modifier = Modifier
) {
    Text(
        text = title,
        style = MeshTypography.Label.copy(
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium
        ),
        color = MeshColors.HomeTextSecondary.copy(alpha = 0.72f),
        textAlign = TextAlign.Center,
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 2.dp, bottom = 4.dp)
    )
}

@Composable
fun WalletHomeTransactionRow(
    tx: WalletTransaction,
    balanceHidden: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val context = LocalContext.current
    val isIncoming = tx.direction == TransactionDirection.INCOMING
    val sign = if (isIncoming) "+" else "-"
    val amountColor = if (isIncoming) MeshColors.Success else MeshColors.HomeTextPrimary
    val timeText = DateFormat.getTimeInstance(DateFormat.SHORT, Locale.getDefault()).format(Date(tx.timestamp))

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(MeshColors.SurfaceElevated),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = if (isIncoming) Icons.Filled.ArrowDownward else Icons.Filled.ArrowUpward,
                contentDescription = null,
                tint = MeshColors.HomeTextPrimary,
                modifier = Modifier.size(16.dp)
            )
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = if (isIncoming) L10n.Transaction.received(context) else L10n.Transaction.sent(context),
                style = MeshTypography.Body.copy(fontSize = 17.sp, fontWeight = FontWeight.Medium),
                color = MeshColors.HomeTextPrimary
            )
            Text(
                text = TronUSDTService.shortAddress(tx.counterpartyAddress),
                style = MeshTypography.Caption,
                color = MeshColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }

        Column(horizontalAlignment = Alignment.End) {
            Text(
                text = "$sign${TronUSDTService.formatUsdtAmount(tx.amount)}",
                style = MeshTypography.Body.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold),
                color = amountColor,
                modifier = Modifier.meshBalancePrivacyBlur(isHidden = balanceHidden, blurRadius = 6.dp)
            )
            Text(
                text = timeText,
                style = MeshTypography.Label,
                color = MeshColors.HomeTextSecondary.copy(alpha = 0.72f)
            )
        }
    }
}
