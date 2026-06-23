package com.mesh.wallet.data.privacy

import com.mesh.wallet.core.config.TronConfiguration
import com.mesh.wallet.core.privacy.PrivacyStore
import com.mesh.wallet.data.MeshWalletCredentials
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.data.secure.WalletRegistry
import com.mesh.wallet.data.tron.TronApiService
import com.mesh.wallet.data.tron.TronTransactionService
import com.mesh.wallet.data.tron.TronUSDTService
import com.mesh.wallet.data.tron.TronWalletService
import com.mesh.wallet.domain.model.WalletReceiveSlot
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import java.math.BigDecimal

class MeshPrivacyService(
    private val registry: WalletRegistry,
    private val secureStorage: SecureStorage,
    private val privacyStore: PrivacyStore,
    private val credentials: MeshWalletCredentials
) {
    data class SpendSource(
        val address: String,
        val derivationPath: String,
        val slotIndex: Int
    )

    sealed class DeepRecoveryProgress {
        data class Scanning(val checked: Int, val total: Int) : DeepRecoveryProgress()
        data class Transferring(val current: Int, val total: Int) : DeepRecoveryProgress()
    }

    suspend fun listWalletReceiveSlots(walletId: String): List<WalletReceiveSlot> {
        val wallet = registry.wallet(walletId) ?: return emptyList()
        if (!credentials.supportsHdWalletFeatures(walletId)) {
            return listOf(
                WalletReceiveSlot(
                    index = 0,
                    address = wallet.address,
                    name = privacyStore.slotName(walletId, 0)
                )
            )
        }
        val words = secureStorage.loadMnemonic(walletId) ?: return emptyList()
        val indices = privacyStore.visibleReceiveSlotIndices(walletId)
        return coroutineScope {
            indices.map { index ->
                async {
                    val address = TronWalletService.deriveReceiveAddress(index, words)
                    val balance = TronApiService.fetchUsdtBalance(address)
                    WalletReceiveSlot(
                        index = index,
                        address = address,
                        name = privacyStore.slotName(walletId, index),
                        balanceUsdt = balance
                    )
                }
            }.awaitAll()
        }
    }

    suspend fun resolveSpendSource(walletId: String, slotIndex: Int): SpendSource {
        val wallet = registry.wallet(walletId) ?: error("Wallet not found")
        if (!credentials.supportsHdWalletFeatures(walletId)) {
            return SpendSource(wallet.address, TronConfiguration.DEFAULT_DERIVATION_PATH, 0)
        }
        val words = secureStorage.loadMnemonic(walletId) ?: error("Mnemonic missing")
        val path = TronConfiguration.receiveDerivationPath(slotIndex)
        val address = TronWalletService.deriveReceiveAddress(slotIndex, words)
        return SpendSource(address, path, slotIndex)
    }

    suspend fun receiveAddress(walletId: String, slotIndex: Int): String =
        resolveSpendSource(walletId, slotIndex).address

    suspend fun totalAvailableUsdt(walletId: String): BigDecimal =
        listWalletReceiveSlots(walletId).mapNotNull { it.balanceUsdt }.fold(BigDecimal.ZERO, BigDecimal::add)

    suspend fun recoverDeepFundsToMainWallet(
        walletId: String,
        onProgress: ((DeepRecoveryProgress) -> Unit)? = null
    ): Int {
        val words = secureStorage.loadMnemonic(walletId) ?: error("Mnemonic missing")
        syncDeepRecoveryFundedIndices(walletId, words, onProgress)

        val mainAddress = TronWalletService.deriveReceiveAddress(0, words)
        val donorIndices = privacyStore.registeredReceiveIndices(walletId).filter { it != 0 }.sorted()

        val donors = mutableListOf<Pair<Int, BigDecimal>>()
        for (index in donorIndices) {
            val address = TronWalletService.deriveReceiveAddress(index, words)
            val balance = TronApiService.fetchUsdtBalance(address) ?: continue
            if (balance > BigDecimal.ZERO) donors.add(index to balance)
            delay(80)
        }
        donors.sortByDescending { it.second }

        onProgress?.invoke(DeepRecoveryProgress.Transferring(0, donors.size))
        var transferCount = 0
        for ((offset, donor) in donors.withIndex()) {
            if (offset > 0) delay(1_200)
            val source = resolveSpendSource(walletId, donor.first)
            val key = credentials.signingKey(walletId, source.derivationPath)
            TronTransactionService.sendUsdt(key, source.address, mainAddress, donor.second)
            transferCount++
            onProgress?.invoke(DeepRecoveryProgress.Transferring(transferCount, donors.size))
        }
        return transferCount
    }

    private suspend fun syncDeepRecoveryFundedIndices(
        walletId: String,
        words: List<String>,
        onProgress: ((DeepRecoveryProgress) -> Unit)?
    ) {
        val total = PrivacyStore.DEEP_RECOVERY_SCAN_COUNT
        var checked = 0
        val batch = 16
        for (start in 0 until total step batch) {
            val end = minOf(start + batch, total)
            for (index in start until end) {
                checked++
                onProgress?.invoke(DeepRecoveryProgress.Scanning(checked, total))
                val address = TronWalletService.deriveReceiveAddress(index, words)
                val balance = TronApiService.fetchUsdtBalance(address) ?: continue
                if (balance > BigDecimal.ZERO) privacyStore.registerReceiveIndex(walletId, index)
            }
            delay(120)
        }
    }
}
