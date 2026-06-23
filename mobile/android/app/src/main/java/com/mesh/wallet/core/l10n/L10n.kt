package com.mesh.wallet.core.l10n

import android.content.Context
import com.mesh.wallet.R

object L10n {
    fun tr(context: Context, key: String, vararg args: Any): String {
        val resId = context.resources.getIdentifier(key, "string", context.packageName)
        if (resId == 0) return key
        return if (args.isEmpty()) context.getString(resId)
        else context.getString(resId, *args)
    }

    object Welcome {
        fun tagline(c: Context) = tr(c, "welcome_tagline")
        fun create(c: Context) = tr(c, "welcome_create")
        fun restore(c: Context) = tr(c, "welcome_restore")
        fun legalPrefix(c: Context) = tr(c, "welcome_legal_prefix")
    }

    object Wallet {
        fun send(c: Context) = tr(c, "wallet_send")
        fun receive(c: Context) = tr(c, "wallet_receive")
        fun activity(c: Context) = tr(c, "wallet_activity")
        fun activityEmpty(c: Context) = tr(c, "wallet_activity_empty")
        fun filterAll(c: Context) = tr(c, "wallet_activity_filter_all")
        fun filterReceived(c: Context) = tr(c, "wallet_activity_filter_received")
        fun filterSent(c: Context) = tr(c, "wallet_activity_filter_sent")
        fun fund(c: Context) = tr(c, "wallet_fund")
        fun today(c: Context) = tr(c, "wallet_today")
        fun homeTotalAmountLabel(c: Context) = tr(c, "wallet_home_total_amount_label")
    }

    object WalletSelect {
        fun title(c: Context) = tr(c, "wallet_select_title")
        fun addExisting(c: Context) = tr(c, "wallet_select_add_existing")
        fun createNew(c: Context) = tr(c, "wallet_select_create_new")
        fun menuRename(c: Context) = tr(c, "wallet_select_menu_rename")
        fun menuBackup(c: Context) = tr(c, "wallet_select_menu_backup")
        fun menuRemove(c: Context) = tr(c, "wallet_select_menu_remove")
    }

    object Send {
        fun title(c: Context) = tr(c, "send_title")
        fun stepAddress(c: Context) = tr(c, "send_step_address")
        fun stepProgress(c: Context) = tr(c, "send_step_progress")
        fun fromAddress(c: Context) = tr(c, "send_from_address")
        fun recipient(c: Context) = tr(c, "send_step_recipient")
        fun addressPlaceholder(c: Context) = tr(c, "send_address_placeholder")
        fun scanQr(c: Context) = tr(c, "send_scan_qr")
        fun sendToSelf(c: Context) = tr(c, "send_send_to_self")
        fun amount(c: Context) = tr(c, "send_step_amount")
        fun useMax(c: Context) = tr(c, "send_use_max")
        fun available(c: Context, amount: String) = tr(c, "send_available", amount)
        fun availableMulti(c: Context, amount: String) = tr(c, "send_available_multi", amount)
        fun availableOnSlot(c: Context, amount: String) = tr(c, "send_available_on_slot", amount)
        fun type(c: Context) = tr(c, "send_step_type")
        fun methodDirect(c: Context) = tr(c, "send_method_direct")
        fun methodDirectDetail(c: Context) = tr(c, "send_method_direct_detail")
        fun methodPrivate(c: Context) = tr(c, "send_method_private")
        fun methodPrivateDetail(c: Context) = tr(c, "send_method_private_detail")
        fun timingDirect(c: Context) = tr(c, "send_timing_direct")
        fun timingPrivate(c: Context) = tr(c, "send_timing_private")
        fun protection(c: Context) = tr(c, "send_step_protection")
        fun noTrxNeeded(c: Context) = tr(c, "send_no_trx_needed")
        fun networkResources(c: Context) = tr(c, "send_network_resources")
        fun feeLabel(c: Context) = tr(c, "send_fee_label")
        fun reviewTitle(c: Context) = tr(c, "send_review_title")
        fun review(c: Context) = tr(c, "send_review_title")
        fun reviewSending(c: Context) = tr(c, "send_review_sending")
        fun reviewTo(c: Context) = tr(c, "send_review_to")
        fun reviewNetwork(c: Context) = tr(c, "send_review_network")
        fun reviewTotal(c: Context) = tr(c, "send_review_total")
        fun reviewArrives(c: Context) = tr(c, "send_review_arrives")
        fun reviewPrivateDeposit(c: Context) = tr(c, "send_review_private_deposit")
        fun reviewWarning(c: Context) = tr(c, "send_warning_review")
        fun slide(c: Context) = tr(c, "send_slide_confirm")
        fun preparing(c: Context) = tr(c, "send_preparing")
        fun keepOpen(c: Context) = tr(c, "send_keep_open")
        fun sent(c: Context) = tr(c, "send_sent")
        fun failed(c: Context) = tr(c, "send_failed")
        fun feeFormat(c: Context, fee: String) = tr(c, "send_fee_format", fee)
    }

    object WalletAddressDrawer {
        fun title(c: Context) = tr(c, "wallet_address_drawer_title")
        fun subtitle(c: Context) = tr(c, "wallet_address_drawer_subtitle")
        fun createAccount(c: Context) = tr(c, "receive_generate_balance")
        fun mainBadge(c: Context) = tr(c, "wallet_address_drawer_main_badge")
        fun totalLabel(c: Context) = tr(c, "wallet_address_drawer_total_label")
    }

    object Common {
        fun next(c: Context) = tr(c, "common_next")
        fun cancel(c: Context) = tr(c, "common_cancel")
        fun continue_(c: Context) = tr(c, "common_continue")
        fun done(c: Context) = tr(c, "common_done")
        fun close(c: Context) = tr(c, "common_close")
        fun copy(c: Context) = tr(c, "common_copy")
        fun copied(c: Context) = tr(c, "common_copied")
        fun paste(c: Context) = tr(c, "common_paste")
        fun ok(c: Context) = tr(c, "common_ok")
    }

    object Transaction {
        fun received(c: Context) = tr(c, "transaction_received")
        fun sent(c: Context) = tr(c, "transaction_sent")
    }
}
