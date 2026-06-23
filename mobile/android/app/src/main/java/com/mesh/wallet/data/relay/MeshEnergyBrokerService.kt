package com.mesh.wallet.data.relay

import com.mesh.wallet.core.network.MeshNetworkSponsorship
import com.mesh.wallet.data.tron.TronApiException
import com.mesh.wallet.data.tron.TronApiService
import kotlinx.coroutines.delay

object MeshEnergyBrokerService {
    private const val PREFERRED_ENERGY = 65_000L
    private const val HIGH_ENERGY_MINIMUM = 55_000L
    private const val STANDARD_ENERGY_MINIMUM = 28_000L

    fun preferredTransferEnergy(): Long = PREFERRED_ENERGY

    fun energyMinimum(highEnergy: Boolean): Long =
        if (highEnergy) HIGH_ENERGY_MINIMUM else STANDARD_ENERGY_MINIMUM

    suspend fun activateTronAddress(address: String) {
        if (!MeshNetworkSponsorship.isEnabled) return
        var lastError: Throwable? = null
        repeat(4) { attempt ->
            runCatching {
                MeshRelayService.activateAddress(address.trim())
            }.onSuccess { return }.onFailure {
                lastError = it
                if (attempt < 3 && isActivationError(it)) delay(12_000)
                else throw it
            }
        }
        throw lastError ?: TronApiException.BroadcastFailed("Activation failed.")
    }

    suspend fun ensureActivatedOnTron(address: String, statusUpdate: ((String) -> Unit)? = null) {
        if (!MeshNetworkSponsorship.isEnabled) return
        val trimmed = address.trim()
        if (trimmed.isEmpty()) return
        if (TronApiService.isAccountActivated(trimmed)) return
        statusUpdate?.invoke("Activating address on Tron…")
        activateTronAddress(trimmed)
    }

    suspend fun prepareSender(
        address: String,
        toAddress: String,
        highEnergy: Boolean = false,
        skipRecipientActivation: Boolean = false
    ) {
        if (!MeshNetworkSponsorship.isEnabled) return
        val tierMinimum = energyMinimum(highEnergy)
        try {
            val response = MeshRelayService.prepareSender(
                address = address,
                toAddress = toAddress,
                highEnergy = highEnergy,
                skipRecipientActivation = skipRecipientActivation
            )
            if (!response.ok) {
                throw TronApiException.BroadcastFailed(response.message ?: "Prepare sender failed")
            }
            settleAfterPrepare(address, response.energy, highEnergy)
        } catch (e: Throwable) {
            if (hasTransferEnergy(address, tierMinimum)) return
            throw e
        }
    }

    suspend fun settleAfterPrepare(address: String, delegatedEnergy: Int?, highEnergy: Boolean) {
        val tierMinimum = energyMinimum(highEnergy)
        val minimumWait = when {
            delegatedEnergy != null && delegatedEnergy >= 130_000 -> 22
            delegatedEnergy != null && delegatedEnergy >= 100_000 -> 20
            delegatedEnergy != null && delegatedEnergy >= 60_000 -> 18
            else -> 16
        }
        repeat(minimumWait) {
            if (hasTransferEnergy(address, tierMinimum)) return
            delay(1_000)
        }
        requireSenderReady(address, tierMinimum)
    }

    suspend fun requireSenderReady(address: String, minimumEnergy: Long = PREFERRED_ENERGY) {
        repeat(30) {
            if (hasTransferEnergy(address, minimumEnergy)) return
            delay(1_000)
        }
        throw TronApiException.BroadcastFailed("Sender energy not ready.")
    }

    suspend fun hasTransferEnergy(address: String, minimum: Long): Boolean {
        val resources = runCatching { TronApiService.fetchAccountResources(address) }.getOrNull() ?: return false
        return resources.energyRemaining >= minimum && resources.bandwidthRemaining > 0
    }

    fun isEnergyRelatedError(error: Throwable): Boolean {
        val text = error.message.orEmpty().lowercase()
        return "energy" in text || "bandwidth" in text || "resource" in text
    }

    private fun isActivationError(error: Throwable): Boolean {
        val text = error.message.orEmpty().lowercase()
        return "activate" in text
    }
}
