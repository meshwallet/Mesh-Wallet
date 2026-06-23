package com.mesh.wallet.core.config

import android.content.Context
import android.content.Intent
import android.net.Uri

object MeshAppLinks {
    const val CONTACT_URL = "https://meshwallet.app/support"

    fun openContactSupport(context: Context) {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(CONTACT_URL)))
    }
}
