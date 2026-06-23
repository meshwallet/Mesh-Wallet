package com.mesh.wallet.ui.send

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.mesh.wallet.core.config.MeshSendFees
import com.mesh.wallet.core.config.TronConfiguration
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.privacy.PrivacyStore
import com.mesh.wallet.core.send.MeshBackgroundSendService
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.privacy.MeshPrivacyService
import com.mesh.wallet.data.tron.SendAmountParser
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.domain.model.WalletReceiveSlot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.text.DecimalFormat

class SendFlowViewModel(
    private val session: WalletSession,
    private val privacyStore: PrivacyStore,
    private val privacyService: MeshPrivacyService,
    private val backgroundSend: MeshBackgroundSendService,
    initialSpendable: BigDecimal? = null
) : ViewModel() {
    private val _recipient = MutableStateFlow("")
    val recipient: StateFlow<String> = _recipient.asStateFlow()

    private val _amountText = MutableStateFlow("")
    val amountText: StateFlow<String> = _amountText.asStateFlow()

    private val _availableUsdt = MutableStateFlow(initialSpendable ?: BigDecimal.ZERO)
    val availableUsdt: StateFlow<BigDecimal> = _availableUsdt.asStateFlow()

    private val _hasLoadedAvailable = MutableStateFlow(initialSpendable != null)
    val hasLoadedAvailable: StateFlow<Boolean> = _hasLoadedAvailable.asStateFlow()

    private val _sendSlots = MutableStateFlow<List<WalletReceiveSlot>>(emptyList())
    val sendSlots: StateFlow<List<WalletReceiveSlot>> = _sendSlots.asStateFlow()

    private val _selectedSlotIndex = MutableStateFlow(0)
    val selectedSlotIndex: StateFlow<Int> = _selectedSlotIndex.asStateFlow()

    private val _isSending = MutableStateFlow(false)
    val isSending: StateFlow<Boolean> = _isSending.asStateFlow()

    private val _sendError = MutableStateFlow<String?>(null)
    val sendError: StateFlow<String?> = _sendError.asStateFlow()

    private val _sendSuccessTxId = MutableStateFlow<String?>(null)
    val sendSuccessTxId: StateFlow<String?> = _sendSuccessTxId.asStateFlow()

    private val _sendProgress = MutableStateFlow<String?>(null)
    val sendProgress: StateFlow<String?> = _sendProgress.asStateFlow()

    val networkFee: BigDecimal get() = MeshSendFees.networkFee()
    val enteredAmount: BigDecimal get() = SendAmountParser.parse(_amountText.value) ?: BigDecimal.ZERO
    val totalDebit: BigDecimal get() = enteredAmount

    val supportsHdWallet: Boolean
        get() = session.credentials.supportsHdWalletFeatures(session.registry.activeWalletId)

    val canSendToSelf: Boolean
        get() = supportsHdWallet && selfTransferDestinationSlots.isNotEmpty()

    val selfTransferDestinationSlots: List<WalletReceiveSlot>
        get() = _sendSlots.value.filter { it.index != _selectedSlotIndex.value && it.address.isNotBlank() }

    init {
        refresh()
    }

    fun refresh() {
        val walletId = session.registry.activeWalletId ?: return
        _selectedSlotIndex.value = privacyStore.selectedSendSlotIndex(walletId)
        viewModelScope.launch {
            val slots = privacyService.listWalletReceiveSlots(walletId)
            _sendSlots.value = slots
            applyAvailableFromSelectedSlot(walletId, slots)
            _hasLoadedAvailable.value = true
        }
    }

    private fun applyAvailableFromSelectedSlot(walletId: String, slots: List<WalletReceiveSlot>) {
        val slot = slots.firstOrNull { it.index == _selectedSlotIndex.value } ?: return
        val total = slots.mapNotNull { it.balanceUsdt }.fold(BigDecimal.ZERO, BigDecimal::add)
        _availableUsdt.value = when {
            slot.index == 0 -> backgroundSend.spendableUsdt(walletId, total)
            else -> slot.balanceUsdt ?: BigDecimal.ZERO
        }
    }

    fun setRecipient(value: String) { _recipient.value = value.trim() }
    private var didLogAmountEntered = false

    fun setAmountText(value: String) {
        _amountText.value = value.filter { it.isDigit() || it == '.' || it == ',' }
        if (!didLogAmountEntered && enteredAmount > BigDecimal.ZERO) {
            didLogAmountEntered = true
        }
    }

    fun setSelectedSlot(index: Int) {
        _selectedSlotIndex.value = index
        session.registry.activeWalletId?.let { walletId ->
            privacyStore.setSelectedSendSlotIndex(walletId, index)
            applyAvailableFromSelectedSlot(walletId, _sendSlots.value)
        }
    }

    fun applySelfTransferRecipient(slot: WalletReceiveSlot) {
        _recipient.value = slot.address
    }

    fun useMaxAmount() {
        _amountText.value = TronUSDTService.formatUsdtAmount(_availableUsdt.value, includeSymbol = false)
    }

    fun availableText(context: Context): String {
        if (!_hasLoadedAvailable.value) {
            return L10n.Send.available(context, "…")
        }
        val amount = TronConfiguration.formatUsdt(_availableUsdt.value, includeSymbol = true)
        return if (_sendSlots.value.size > 1) {
            L10n.Send.availableOnSlot(context, amount)
        } else {
            L10n.Send.available(context, amount)
        }
    }

    fun canProceedToReview(): Boolean = passesSendFormChecks(includeBalance = true)

    fun passesSendFormChecks(includeBalance: Boolean): Boolean {
        if (!TronUSDTService.isValidTronAddress(_recipient.value)) return false
        val amount = enteredAmount
        if (amount <= BigDecimal.ZERO) return false
        if (MeshSendFees.showsFeeInUI && networkFee > BigDecimal.ZERO && amount <= networkFee) return false
        if (includeBalance && totalDebit > _availableUsdt.value) return false
        return true
    }

    fun executeSend() {
        val walletId = session.registry.activeWalletId ?: return
        if (!canProceedToReview()) return
        _isSending.value = true
        _sendError.value = null
        backgroundSend.beginSend(
            walletId = walletId,
            recipientAddress = _recipient.value,
            amount = enteredAmount,
            amountText = _amountText.value,
            slotIndex = _selectedSlotIndex.value,
            onProgress = { _sendProgress.value = it }
        ) { result ->
            _isSending.value = false
            result.onSuccess { txId ->
                _sendSuccessTxId.value = txId
            }.onFailure { error ->
                _sendError.value = error.message
                    _selectedSlotIndex.value,
                    error.message
                )
            }
        }
    }

    fun formattedFee(): String = MeshSendFees.formattedFee(networkFee)

    fun reviewAmountText(): String {
        val formatter = DecimalFormat("#,##0.00")
        return "${formatter.format(enteredAmount)} USDT"
    }

    fun reviewTotalText(): String {
        val formatter = DecimalFormat("#,##0.00")
        return "${formatter.format(totalDebit)} USDT"
    }

    fun reviewArrivesText(context: Context): String = L10n.Send.timingDirect(context)

    fun resetOutcome() {
        _sendSuccessTxId.value = null
        _sendError.value = null
        _sendProgress.value = null
    }

    companion object {
        fun factory(session: WalletSession, initialSpendable: BigDecimal? = null): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return SendFlowViewModel(
                        session = session,
                        privacyStore = session.privacyStore,
                        privacyService = session.privacyService,
                        backgroundSend = session.backgroundSendService,
                        initialSpendable = initialSpendable
                    ) as T
                }
            }
    }
}
