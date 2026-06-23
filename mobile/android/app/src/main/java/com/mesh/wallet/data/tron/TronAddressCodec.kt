package com.mesh.wallet.data.tron

object TronAddressCodec {
    fun matches(a: String, b: String): Boolean =
        normalize(a).equals(normalize(b), ignoreCase = true)

    fun normalize(address: String): String = address.trim()
}
