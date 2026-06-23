package com.mesh.wallet

import android.app.Application
import com.mesh.wallet.core.session.WalletSession

class MeshApplication : Application() {
    lateinit var walletSession: WalletSession
        private set

    override fun onCreate() {
        super.onCreate()
        System.loadLibrary("TrustWalletCore")
        walletSession = WalletSession(this)
        walletSession.reconcile()
    }
}
