package com.mesh.wallet.core.security

import android.app.Activity
import android.graphics.Color
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import com.mesh.wallet.R

object MeshPrivacyShield {
    private const val OVERLAY_TAG = "mesh_privacy_shield"
    var isSuppressed = false
    var hasBeenActive = false

    fun presentIfAllowed(activity: Activity) {
        if (!hasBeenActive || isSuppressed) return
        val root = activity.window.decorView as? ViewGroup ?: return
        if (root.findViewWithTag<FrameLayout>(OVERLAY_TAG) != null) return

        val container = FrameLayout(activity).apply {
            tag = OVERLAY_TAG
            setBackgroundColor(Color.argb(220, 0, 0, 0))
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            isClickable = false
        }
        val icon = ImageView(activity).apply {
            setImageResource(R.drawable.icon_png)
            scaleType = ImageView.ScaleType.FIT_CENTER
            alpha = 0.9f
        }
        container.addView(
            icon,
            FrameLayout.LayoutParams(
                (activity.resources.displayMetrics.widthPixels * 0.4f).toInt(),
                (activity.resources.displayMetrics.widthPixels * 0.4f).toInt()
            ).apply { gravity = android.view.Gravity.CENTER }
        )
        root.addView(container)
    }

    fun dismiss(activity: Activity) {
        val root = activity.window.decorView as? ViewGroup ?: return
        root.findViewWithTag<FrameLayout>(OVERLAY_TAG)?.let { root.removeView(it) }
    }
}
