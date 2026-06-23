package com.mesh.wallet

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.fragment.app.FragmentActivity
import com.mesh.wallet.core.security.MeshPrivacyShield
import com.mesh.wallet.ui.MeshApp
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshTheme

class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { keepSystemSplashOnScreen }
        splashScreen.setOnExitAnimationListener { splashScreenViewProvider ->
            splashScreenViewProvider.remove()
        }
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val session = (application as MeshApplication).walletSession

        setContent {
            MeshTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MeshColors.Background) {
                    MeshApp(session = session)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        MeshPrivacyShield.hasBeenActive = true
        MeshPrivacyShield.dismiss(this)
    }

    override fun onPause() {
        MeshPrivacyShield.presentIfAllowed(this)
        super.onPause()
    }

    companion object {
        @Volatile
        var keepSystemSplashOnScreen: Boolean = true
    }
}
