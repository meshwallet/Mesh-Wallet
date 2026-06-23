package com.mesh.wallet.ui.send

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.ui.components.MeshFlowScreenHeader
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.components.MeshSendFieldButton
import com.mesh.wallet.ui.components.MeshSlideToSend
import com.mesh.wallet.ui.components.MeshWalletSlotPicker
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

private enum class SendStep { Address, Review, Success, Failed }

@Composable
fun SendFlowHost(viewModel: SendFlowViewModel, onClose: () -> Unit) {
    var step by remember { mutableStateOf(SendStep.Address) }
    val successTx by viewModel.sendSuccessTxId.collectAsState()
    val sendError by viewModel.sendError.collectAsState()
    val sendProgress by viewModel.sendProgress.collectAsState()
    val context = LocalContext.current
    var showQr by remember { mutableStateOf(false) }
    var showSendToSelf by remember { mutableStateOf(false) }

    androidx.compose.runtime.LaunchedEffect(Unit) {
    }

    androidx.compose.runtime.LaunchedEffect(successTx) {
        if (successTx != null) step = SendStep.Success
    }
    androidx.compose.runtime.LaunchedEffect(sendError) {
        if (sendError != null) step = SendStep.Failed
    }

    Box(modifier = Modifier.fillMaxSize().background(MeshColors.Background)) {
        Column(modifier = Modifier.fillMaxSize()) {
            when (step) {
                SendStep.Address -> SendAddressStep(
                    viewModel = viewModel,
                    onClose = onClose,
                    onPaste = { pasteFromClipboard(context, viewModel) },
                    onScanQr = { showQr = true },
                    onSendToSelf = { showSendToSelf = true },
                    onReview = {
                        if (viewModel.canProceedToReview()) {
                            step = SendStep.Review
                        }
                    }
                )
                SendStep.Review -> SendReviewStep(
                    viewModel = viewModel,
                    progress = sendProgress,
                    onBack = { step = SendStep.Address },
                    onSend = { viewModel.executeSend() }
                )
                SendStep.Success -> SendOutcome(
                    title = L10n.Send.sent(context),
                    subtitle = successTx.orEmpty(),
                    onDone = onClose
                )
                SendStep.Failed -> SendOutcome(
                    title = L10n.Send.failed(context),
                    subtitle = sendError.orEmpty(),
                    onDone = {
                        viewModel.resetOutcome()
                        step = SendStep.Review
                    }
                )
            }
        }

        val isSending by viewModel.isSending.collectAsState()
        if (isSending && step == SendStep.Review) {
            SendProgressOverlay(progress = sendProgress)
        }
    }

    TronQRScannerSheet(
        visible = showQr,
        onDismiss = { showQr = false },
        onScanned = { viewModel.setRecipient(it) }
    )

    MeshSendToSelfSheet(
        visible = showSendToSelf,
        slots = viewModel.selfTransferDestinationSlots,
        onDismiss = { showSendToSelf = false },
        onSelect = {
            viewModel.applySelfTransferRecipient(it)
            showSendToSelf = false
        }
    )
}

@Composable
private fun ColumnScope.SendAddressStep(
    viewModel: SendFlowViewModel,
    onClose: () -> Unit,
    onPaste: () -> Unit,
    onScanQr: () -> Unit,
    onSendToSelf: () -> Unit,
    onReview: () -> Unit
) {
    val context = LocalContext.current
    val recipient by viewModel.recipient.collectAsState()
    val amount by viewModel.amountText.collectAsState()
    val sendSlots by viewModel.sendSlots.collectAsState()
    val selectedSlot by viewModel.selectedSlotIndex.collectAsState()
    val scroll = rememberScrollState()

    MeshFlowScreenHeader(
        title = L10n.Send.title(context),
        onClose = onClose,
        trailingText = L10n.Send.stepAddress(context)
    )

    Column(
        modifier = Modifier
            .weight(1f)
            .verticalScroll(scroll)
            .padding(horizontal = MeshMetrics.ScreenPadding)
    ) {
        Spacer(modifier = Modifier.height(8.dp))

        if (viewModel.supportsHdWallet && sendSlots.isNotEmpty()) {
            MeshWalletSlotPicker(
                headerTitle = L10n.Send.fromAddress(context),
                slots = sendSlots,
                selectedIndex = selectedSlot,
                onSelect = viewModel::setSelectedSlot
            )
            Spacer(modifier = Modifier.height(28.dp))
        }

        SectionLabel(L10n.Send.recipient(context))
        Spacer(modifier = Modifier.height(12.dp))
        MeshTextField(
            value = recipient,
            onValueChange = viewModel::setRecipient,
            placeholder = L10n.Send.addressPlaceholder(context)
        )
        Spacer(modifier = Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MeshSendFieldButton(Icons.Default.ContentPaste, L10n.Common.paste(context), onPaste)
            MeshSendFieldButton(Icons.Default.QrCodeScanner, L10n.Send.scanQr(context), onScanQr)
            if (viewModel.canSendToSelf) {
                MeshSendFieldButton(Icons.Default.SwapHoriz, L10n.Send.sendToSelf(context), onSendToSelf)
            }
        }

        Spacer(modifier = Modifier.height(28.dp))
        SectionLabel(L10n.Send.amount(context))
        Spacer(modifier = Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            BasicTextField(
                value = amount,
                onValueChange = viewModel::setAmountText,
                textStyle = MeshTypography.BalanceHero.copy(color = MeshColors.TextPrimary),
                cursorBrush = SolidColor(MeshColors.Accent),
                modifier = Modifier.weight(1f),
                decorationBox = { inner ->
                    Box {
                        if (amount.isEmpty()) {
                            Text("0", style = MeshTypography.BalanceHero, color = MeshColors.TextTertiary)
                        }
                        inner()
                    }
                }
            )
            Text("USDT", style = MeshTypography.SectionTitle.copy(fontSize = 22.sp), color = MeshColors.TextSecondary)
        }
        Spacer(modifier = Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                L10n.Send.useMax(context),
                style = MeshTypography.Caption,
                color = MeshColors.TextPrimary,
                modifier = Modifier
                    .border(1.dp, MeshColors.Border, RoundedCornerShape(50))
                    .clickable { viewModel.useMaxAmount() }
                    .padding(horizontal = 14.dp, vertical = 8.dp)
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                viewModel.availableText(context),
                style = MeshTypography.Caption,
                color = MeshColors.TextSecondary,
                textAlign = TextAlign.End
            )
        }

        Spacer(modifier = Modifier.height(28.dp))
        ProtectionSection(feeText = viewModel.formattedFee())

        Spacer(modifier = Modifier.height(24.dp))
    }

    MeshPrimaryButton(
        title = L10n.Common.next(context),
        onClick = onReview,
        enabled = viewModel.canProceedToReview(),
        modifier = Modifier.padding(horizontal = MeshMetrics.ScreenPadding, vertical = 16.dp)
    )
}

@Composable
private fun ProtectionSection(feeText: String) {
    val context = LocalContext.current
    Column {
        SectionLabel(L10n.Send.protection(context))
        Spacer(modifier = Modifier.height(12.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MeshColors.ListCardFill, RoundedCornerShape(MeshMetrics.WalletCardRadius))
                .padding(18.dp)
        ) {
            ProtectionRow(L10n.Send.noTrxNeeded(context), "✓")
            Spacer(modifier = Modifier.height(14.dp))
            ProtectionRow(L10n.Send.networkResources(context), "✓")
            Spacer(modifier = Modifier.height(14.dp))
            ProtectionRow(L10n.Send.feeLabel(context), feeText)
        }
    }
}

@Composable
private fun ProtectionRow(label: String, detail: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MeshTypography.Body, color = MeshColors.TextPrimary)
        Text(detail, style = MeshTypography.Body, color = MeshColors.TextSecondary)
    }
}

@Composable
private fun ColumnScope.SendReviewStep(
    viewModel: SendFlowViewModel,
    progress: String?,
    onBack: () -> Unit,
    onSend: () -> Unit
) {
    val context = LocalContext.current
    val recipient by viewModel.recipient.collectAsState()
    val isSending by viewModel.isSending.collectAsState()

    MeshFlowScreenHeader(
        title = L10n.Send.reviewTitle(context),
        onClose = onBack,
        trailingText = L10n.Send.stepProgress(context),
        usesBackButton = true
    )

    Column(
        modifier = Modifier
            .weight(1f)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = MeshMetrics.ScreenPadding)
    ) {
        Spacer(modifier = Modifier.height(8.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MeshColors.ListCardFill, RoundedCornerShape(MeshMetrics.WalletCardRadius))
                .padding(18.dp)
        ) {
            Text(L10n.Send.reviewSending(context), style = MeshTypography.Caption, color = MeshColors.TextSecondary)
            Text(viewModel.reviewAmountText(), style = MeshTypography.ScreenTitle.copy(fontSize = 28.sp), color = MeshColors.TextPrimary)
            Spacer(modifier = Modifier.height(14.dp))
            Text(L10n.Send.reviewTo(context), style = MeshTypography.Caption, color = MeshColors.TextSecondary)
            Text(TronUSDTService.shortAddress(recipient), style = MeshTypography.SectionTitle, color = MeshColors.TextPrimary)
        }

        Spacer(modifier = Modifier.height(16.dp))
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MeshColors.ListCardFill, RoundedCornerShape(MeshMetrics.WalletCardRadius))
                .padding(vertical = 4.dp)
        ) {
            ReviewRow(L10n.Send.reviewNetwork(context), "TRC-20")
            HorizontalDivider(color = MeshColors.BorderSubtle, modifier = Modifier.padding(start = 16.dp))
            ReviewRow(L10n.Send.feeLabel(context), viewModel.formattedFee())
            HorizontalDivider(color = MeshColors.BorderSubtle, modifier = Modifier.padding(start = 16.dp))
            ReviewRow(L10n.Send.reviewTotal(context), viewModel.reviewTotalText())
            HorizontalDivider(color = MeshColors.BorderSubtle, modifier = Modifier.padding(start = 16.dp))
            ReviewRow(L10n.Send.reviewArrives(context), viewModel.reviewArrivesText(context))
        }

        progress?.let {
            Spacer(modifier = Modifier.height(12.dp))
            Text(it, style = MeshTypography.Caption, color = MeshColors.Accent)
        }

        Spacer(modifier = Modifier.height(8.dp))
        Text(L10n.Send.reviewWarning(context), style = MeshTypography.Caption, color = MeshColors.TextTertiary)
        Spacer(modifier = Modifier.height(24.dp))
    }

    MeshSlideToSend(
        title = L10n.Send.slide(context),
        enabled = !isSending && viewModel.canProceedToReview(),
        onConfirmed = onSend,
        modifier = Modifier.padding(horizontal = MeshMetrics.ScreenPadding, vertical = 16.dp)
    )
}

@Composable
private fun SendProgressOverlay(progress: String?) {
    val context = LocalContext.current
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.72f)),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = MeshColors.Accent)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                progress ?: L10n.Send.preparing(context),
                style = MeshTypography.Secondary,
                color = MeshColors.TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 32.dp)
            )
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                L10n.Send.keepOpen(context),
                style = MeshTypography.Body,
                color = MeshColors.TextPrimary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 28.dp)
            )
        }
    }
}

@Composable
private fun ColumnScope.SendOutcome(title: String, subtitle: String, onDone: () -> Unit) {
    val context = LocalContext.current
    Spacer(modifier = Modifier.height(48.dp))
    Text(title, style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary, modifier = Modifier.padding(horizontal = MeshMetrics.ScreenPadding))
    Spacer(modifier = Modifier.height(12.dp))
    Text(subtitle, style = MeshTypography.Body, color = MeshColors.TextSecondary, modifier = Modifier.padding(horizontal = MeshMetrics.ScreenPadding))
    Spacer(modifier = Modifier.weight(1f))
    MeshPrimaryButton(L10n.Common.done(context), onClick = onDone, modifier = Modifier.padding(MeshMetrics.ScreenPadding))
}

@Composable
private fun ReviewRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, style = MeshTypography.Secondary, color = MeshColors.TextSecondary)
        Text(value, style = MeshTypography.Body, color = MeshColors.TextPrimary)
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text, style = MeshTypography.Caption, color = MeshColors.TextSecondary)
}

@Composable
private fun MeshTextField(value: String, onValueChange: (String) -> Unit, placeholder: String) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        textStyle = MeshTypography.Body.copy(color = MeshColors.TextPrimary),
        cursorBrush = SolidColor(MeshColors.Accent),
        modifier = Modifier
            .fillMaxWidth()
            .background(MeshColors.FieldFill, RoundedCornerShape(MeshMetrics.FieldRadius))
            .padding(16.dp),
        decorationBox = { inner ->
            Box {
                if (value.isEmpty()) {
                    Text(placeholder, style = MeshTypography.Body, color = MeshColors.TextTertiary)
                }
                inner()
            }
        }
    )
}

private fun pasteFromClipboard(context: Context, viewModel: SendFlowViewModel) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
    val text = clipboard?.primaryClip?.getItemAt(0)?.text?.toString().orEmpty()
    if (text.isNotBlank()) viewModel.setRecipient(text)
}
