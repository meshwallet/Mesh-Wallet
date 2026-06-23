package com.mesh.wallet.core.network

import com.mesh.wallet.BuildConfig

object MeshNetworkSponsorship {
    const val isEnabled: Boolean = true

    val relayBaseUrl: String? = BuildConfig.RELAY_URL.trim().takeIf { it.isNotEmpty() }

    val isRelayConfigured: Boolean get() = relayBaseUrl != null

    val relayAuthSecret: String? = BuildConfig.RELAY_AUTH.trim().takeIf { it.isNotEmpty() }
}
