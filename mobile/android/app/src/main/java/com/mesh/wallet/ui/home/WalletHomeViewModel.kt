package com.mesh.wallet.ui.home

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.mesh.wallet.core.privacy.PrivacyStore
import com.mesh.wallet.core.send.MeshBackgroundSendService
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.privacy.MeshPrivacyService
import com.mesh.wallet.data.tron.TronApiService
import com.mesh.wallet.domain.model.TransactionDirection
import com.mesh.wallet.domain.model.WalletReceiveSlot
import com.mesh.wallet.domain.model.WalletTransaction
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.math.BigDecimal
import java.text.DecimalFormat

enum class ActivityFilter { All, Received, Sent }

class WalletHomeViewModel(
    private val session: WalletSession,
    private val privacyStore: PrivacyStore,
    private val privacyService: MeshPrivacyService,
    private val backgroundSend: MeshBackgroundSendService
) : ViewModel() {
    private val _walletName = MutableStateFlow("Wallet")
    val walletName: StateFlow<String> = _walletName.asStateFlow()

    private val _walletAddress = MutableStateFlow("")
    val walletAddress: StateFlow<String> = _walletAddress.asStateFlow()

    private val _usdtBalance = MutableStateFlow(BigDecimal.ZERO)
    val usdtBalance: StateFlow<BigDecimal> = _usdtBalance.asStateFlow()

    private val _focusedSlotBalance = MutableStateFlow(BigDecimal.ZERO)
    val focusedSlotBalance: StateFlow<BigDecimal> = _focusedSlotBalance.asStateFlow()

    private val _receiveSlots = MutableStateFlow<List<WalletReceiveSlot>>(emptyList())
    val receiveSlots: StateFlow<List<WalletReceiveSlot>> = _receiveSlots.asStateFlow()

    private val _focusedSlotIndex = MutableStateFlow(0)
    val focusedSlotIndex: StateFlow<Int> = _focusedSlotIndex.asStateFlow()

    val activeWalletId: String? get() = session.registry.activeWalletId

    private val _transactions = MutableStateFlow<List<WalletTransaction>>(emptyList())
    val transactions: StateFlow<List<WalletTransaction>> = _transactions.asStateFlow()

    private val _filteredTransactions = MutableStateFlow<List<WalletTransaction>>(emptyList())
    val filteredTransactions: StateFlow<List<WalletTransaction>> = _filteredTransactions.asStateFlow()

    private val _activityFilter = MutableStateFlow(ActivityFilter.All)
    val activityFilter: StateFlow<ActivityFilter> = _activityFilter.asStateFlow()

    private val _isInitialLoading = MutableStateFlow(true)
    val isInitialLoading: StateFlow<Boolean> = _isInitialLoading.asStateFlow()

    private val _isPullRefreshing = MutableStateFlow(false)
    val isPullRefreshing: StateFlow<Boolean> = _isPullRefreshing.asStateFlow()

    private val _loadError = MutableStateFlow<String?>(null)
    val loadError: StateFlow<String?> = _loadError.asStateFlow()

    private val _wallets = MutableStateFlow(session.registry.wallets)
    val wallets: StateFlow<List<com.mesh.wallet.domain.model.StoredWallet>> = _wallets.asStateFlow()

    private val _showsMultiAccountChrome = MutableStateFlow(false)
    val showsMultiAccountChrome: StateFlow<Boolean> = _showsMultiAccountChrome.asStateFlow()

    private var pollJob: Job? = null
    private var fullTransactions: List<WalletTransaction> = emptyList()
    private var hasLoadedOnce = false

    val formattedBalance: String get() = balanceFormatter.format(_focusedSlotBalance.value)
    val formattedWalletTotal: String get() = balanceFormatter.format(_usdtBalance.value)

    val showsHomeAccountCaption: Boolean
        get() {
            val walletId = session.registry.activeWalletId ?: return false
            return session.credentials.supportsHdWalletFeatures(walletId)
        }

    fun focusedAccountTitle(fallback: String): String {
        val slot = _receiveSlots.value.firstOrNull { it.index == _focusedSlotIndex.value }
        return slot?.name?.takeIf { it.isNotBlank() } ?: fallback
    }

    val canAddReceiveAddress: Boolean
        get() {
            val walletId = session.registry.activeWalletId ?: return false
            return session.credentials.supportsHdWalletFeatures(walletId) &&
                privacyStore.visibleReceiveSlotCount(walletId) < privacyStore.walletReceiveSlotCount()
        }

    init {
        session.reconcile()
        refreshWallet()
        startPolling()
    }

    fun refreshWallet() {
        val wallet = session.activeWallet.value ?: session.registry.activeWalletId?.let { session.registry.wallet(it) }
        if (wallet == null) return
        _walletName.value = wallet.name
        _walletAddress.value = wallet.address
        _wallets.value = session.registry.wallets
        privacyStore.ensureDefaultReceiveSetup(wallet.id)
        _focusedSlotIndex.value = privacyStore.selectedReceiveSlotIndex(wallet.id)
        _showsMultiAccountChrome.value =
            session.credentials.supportsHdWalletFeatures(wallet.id) &&
                privacyStore.visibleReceiveSlotCount(wallet.id) > 1
        loadData(wallet.id, showUserRefresh = false)
    }

    fun pullToRefresh() {
        val walletId = session.registry.activeWalletId ?: return
        loadData(walletId, showUserRefresh = true)
    }

    fun setFocusedSlot(index: Int) {
        val walletId = session.registry.activeWalletId ?: return
        privacyStore.setSelectedReceiveSlotIndex(walletId, index)
        _focusedSlotIndex.value = index
        val slot = _receiveSlots.value.firstOrNull { it.index == index }
        _focusedSlotBalance.value = slot?.balanceUsdt ?: BigDecimal.ZERO
        applyActivityFilter()
    }

    fun setActivityFilter(filter: ActivityFilter) {
        _activityFilter.value = filter
        applyActivityFilter()
    }

    fun switchWallet(walletId: String) {
        session.setActiveWallet(walletId)
        refreshWallet()
    }

    fun renameWallet(walletId: String, name: String) {
        session.registry.renameWallet(walletId, name)
        refreshWallet()
    }

    fun addReceiveAddress(): Boolean {
        val walletId = session.registry.activeWalletId ?: return false
        val newIndex = privacyStore.addReceiveAddress(walletId)
        if (newIndex != null) {
            refreshWallet()
            return true
        }
        return false
    }

    private fun loadData(walletId: String, showUserRefresh: Boolean) {
        viewModelScope.launch {
            if (showUserRefresh) {
                _isPullRefreshing.value = true
            } else if (!hasLoadedOnce) {
                _isInitialLoading.value = true
            }
            _loadError.value = null
            runCatching {
                val slots = privacyService.listWalletReceiveSlots(walletId)
                _receiveSlots.value = slots
                val total = slots.mapNotNull { it.balanceUsdt }.fold(BigDecimal.ZERO, BigDecimal::add)
                val spendable = backgroundSend.spendableUsdt(walletId, total)
                _usdtBalance.value = spendable
                val focused = slots.firstOrNull { it.index == _focusedSlotIndex.value }
                _focusedSlotBalance.value = focused?.balanceUsdt ?: spendable

                val focusedAddress = focused?.address ?: _walletAddress.value
                fullTransactions = TronApiService.fetchUsdtTransactions(focusedAddress)
                _transactions.value = fullTransactions
                applyActivityFilter()
            }.onFailure { _loadError.value = it.message }

            hasLoadedOnce = true
            _isInitialLoading.value = false
            _isPullRefreshing.value = false
        }
    }

    private fun applyActivityFilter() {
        val filtered = when (_activityFilter.value) {
            ActivityFilter.All -> fullTransactions
            ActivityFilter.Received -> fullTransactions.filter { it.direction == TransactionDirection.INCOMING }
            ActivityFilter.Sent -> fullTransactions.filter { it.direction == TransactionDirection.OUTGOING }
        }
        _filteredTransactions.value = filtered
    }

    private fun startPolling() {
        pollJob?.cancel()
        pollJob = viewModelScope.launch {
            while (isActive) {
                delay(15_000)
                session.registry.activeWalletId?.let { loadData(it, showUserRefresh = false) }
            }
        }
    }

    override fun onCleared() {
        pollJob?.cancel()
        super.onCleared()
    }

    companion object {
        private val balanceFormatter = DecimalFormat("#,##0.00")

        fun factory(session: WalletSession, @Suppress("UNUSED_PARAMETER") context: Context): ViewModelProvider.Factory =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    return WalletHomeViewModel(
                        session,
                        session.privacyStore,
                        session.privacyService,
                        session.backgroundSendService
                    ) as T
                }
            }
    }
}
