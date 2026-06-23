package com.mesh.wallet.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.domain.model.WalletTransaction
import com.mesh.wallet.ui.components.MeshEdgeDismissWrapper
import com.mesh.wallet.ui.components.PresentationEdge
import com.mesh.wallet.ui.home.WalletHomeScreen
import com.mesh.wallet.ui.home.WalletHomeViewModel
import com.mesh.wallet.ui.lock.AppLockScreen
import com.mesh.wallet.ui.navigation.MeshNavRoutes
import com.mesh.wallet.ui.onboarding.AddExistingScreen
import com.mesh.wallet.ui.onboarding.BiometricScreen
import com.mesh.wallet.ui.onboarding.CreateLaunchScreen
import com.mesh.wallet.ui.onboarding.OnboardingViewModel
import com.mesh.wallet.ui.onboarding.PasscodeScreen
import com.mesh.wallet.ui.onboarding.RestorePhraseScreen
import com.mesh.wallet.ui.onboarding.SeedPhraseSecuritySheet
import com.mesh.wallet.ui.onboarding.RestorePrivateKeyScreen
import com.mesh.wallet.ui.onboarding.WalletReadyScreen
import com.mesh.wallet.ui.onboarding.WelcomeScreen
import com.mesh.wallet.ui.privacy.WalletPrivacyScreen
import com.mesh.wallet.ui.receive.ReceiveScreen
import com.mesh.wallet.ui.security.WalletSecurityScreen
import com.mesh.wallet.ui.send.SendFlowHost
import com.mesh.wallet.ui.send.SendFlowViewModel
import com.mesh.wallet.MainActivity
import com.mesh.wallet.ui.splash.MeshSplashView
import com.mesh.wallet.ui.wallet.TransactionDetailSheet

private enum class HomeOverlay { None, Send, Receive, Security, Privacy }

@Composable
fun MeshApp(session: WalletSession) {
    val navController = rememberNavController()
    val context = LocalContext.current
    val activity = context as FragmentActivity
    val onboardingViewModel: OnboardingViewModel = viewModel(factory = OnboardingViewModel.factory(session))
    val homeViewModel: WalletHomeViewModel = viewModel(factory = WalletHomeViewModel.factory(session, context))
    val sendViewModel: SendFlowViewModel = viewModel(factory = SendFlowViewModel.factory(session))

    var showBiometricBackdrop by remember { mutableStateOf(false) }
    var homeOverlay by remember { mutableStateOf(HomeOverlay.None) }
    var selectedTransaction by remember { mutableStateOf<WalletTransaction?>(null) }
    var showSeedSecurity by remember { mutableStateOf(false) }
    var didFinishLaunchRouting by remember { mutableStateOf(false) }
    var addingWalletFromHome by remember { mutableStateOf(false) }

    val isUnlocked by session.appLockController.isUnlocked.collectAsState()

    LaunchedEffect(Unit) {
        session.reconcile()
        val start = if (session.requiresPasscodeOnLaunch && session.secureStorage.isBiometricEnabled()) {
            showBiometricBackdrop = true
            val unlocked = session.appLockController.attemptLaunchBiometricUnlock(activity)
            showBiometricBackdrop = false
            if (unlocked) {
                session.appLockController.unlockForCurrentSession()
                MeshNavRoutes.Home
            } else {
                when {
                    session.hasActiveWallet && session.requiresPasscodeOnLaunch && !isUnlocked -> MeshNavRoutes.Lock
                    session.hasActiveWallet -> MeshNavRoutes.Home
                    else -> MeshNavRoutes.Welcome
                }
            }
        } else {
            when {
                session.hasActiveWallet && session.requiresPasscodeOnLaunch && !isUnlocked -> MeshNavRoutes.Lock
                session.hasActiveWallet -> MeshNavRoutes.Home
                else -> MeshNavRoutes.Welcome
            }
        }
        navController.navigate(start) {
            popUpTo(MeshNavRoutes.Splash) { inclusive = true }
        }
        didFinishLaunchRouting = true
        withFrameNanos { }
        withFrameNanos { }
        MainActivity.keepSystemSplashOnScreen = false
    }

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(navController = navController, startDestination = MeshNavRoutes.Splash) {
            composable(MeshNavRoutes.Splash) {
                MeshSplashView()
            }
            composable(MeshNavRoutes.Lock) {
                AppLockScreen(
                    session = session,
                    onUnlocked = {
                        session.appLockController.unlockForCurrentSession()
                        navController.navigate(MeshNavRoutes.Home) {
                            popUpTo(MeshNavRoutes.Lock) { inclusive = true }
                        }
                    }
                )
            }
            composable(MeshNavRoutes.Welcome) {
                WelcomeScreen(
                    onCreate = { navController.navigate(MeshNavRoutes.CreateLaunch) },
                    onRestore = { navController.navigate(MeshNavRoutes.AddExisting) }
                )
            }
            composable(MeshNavRoutes.AddExisting) {
                SeedPhraseSecuritySheet(
                    visible = showSeedSecurity,
                    onDismiss = { showSeedSecurity = false },
                    onContinue = {
                        showSeedSecurity = false
                        navController.navigate(MeshNavRoutes.RestorePhrase)
                    }
                )
                AddExistingScreen(
                    onBack = { navController.popBackStack() },
                    onPhrase = { showSeedSecurity = true },
                    onPrivateKey = { navController.navigate(MeshNavRoutes.RestorePrivateKey) }
                )
            }
            composable(MeshNavRoutes.RestorePhrase) {
                RestorePhraseScreen(onboardingViewModel, session, { navController.popBackStack() }) {
                    if (addingWalletFromHome) finishAddWalletFromHome(navController, onboardingViewModel, session, homeViewModel) { addingWalletFromHome = false }
                    else navController.navigate(MeshNavRoutes.PasscodeCreate)
                }
            }
            composable(MeshNavRoutes.RestorePrivateKey) {
                RestorePrivateKeyScreen(onboardingViewModel, session, { navController.popBackStack() }) {
                    if (addingWalletFromHome) finishAddWalletFromHome(navController, onboardingViewModel, session, homeViewModel) { addingWalletFromHome = false }
                    else navController.navigate(MeshNavRoutes.PasscodeCreate)
                }
            }
            composable(MeshNavRoutes.CreateLaunch) {
                CreateLaunchScreen(onboardingViewModel, { navController.popBackStack() }) {
                    navController.navigate(MeshNavRoutes.PasscodeCreate)
                }
            }
            composable(MeshNavRoutes.PasscodeCreate) {
                PasscodeScreen("Create passcode", onComplete = {
                    onboardingViewModel.setPendingPasscode(it)
                    navController.navigate(MeshNavRoutes.PasscodeConfirm)
                })
            }
            composable(MeshNavRoutes.PasscodeConfirm) {
                PasscodeScreen("Confirm passcode", validate = { it == onboardingViewModel.pendingPasscode }) {
                    onboardingViewModel.commitPasscode()
                    navController.navigate(MeshNavRoutes.Biometric)
                }
            }
            composable(MeshNavRoutes.Biometric) {
                BiometricScreen(session, onEnable = {
                    session.secureStorage.setBiometricEnabled(true)
                    completeWalletSetup(
                        addingWalletFromHome = addingWalletFromHome,
                        navController = navController,
                        onboardingViewModel = onboardingViewModel,
                        session = session,
                        homeViewModel = homeViewModel,
                        onAddWalletDone = { addingWalletFromHome = false }
                    )
                }, onSkip = {
                    completeWalletSetup(
                        addingWalletFromHome = addingWalletFromHome,
                        navController = navController,
                        onboardingViewModel = onboardingViewModel,
                        session = session,
                        homeViewModel = homeViewModel,
                        onAddWalletDone = { addingWalletFromHome = false }
                    )
                })
            }
            composable(MeshNavRoutes.WalletReady) {
                WalletReadyScreen {
                    navController.navigate(MeshNavRoutes.Home) {
                        popUpTo(MeshNavRoutes.Welcome) { inclusive = true }
                    }
                }
            }
            composable(MeshNavRoutes.Home) {
                val unlocked by session.appLockController.isUnlocked.collectAsState()
                if (session.secureStorage.isPasscodeEnabled() && session.hasActiveWallet && !unlocked) {
                    AppLockScreen(session = session, onUnlocked = { session.appLockController.unlock() })
                } else {
                    WalletHomeScreen(
                        viewModel = homeViewModel,
                        session = session,
                        onSend = { homeOverlay = HomeOverlay.Send; sendViewModel.refresh() },
                        onReceive = {
                            homeOverlay = HomeOverlay.Receive
                        },
                        onSecurity = { homeOverlay = HomeOverlay.Security },
                        onPrivacy = { homeOverlay = HomeOverlay.Privacy },
                        onTransactionClick = { selectedTransaction = it },
                        onCreateWallet = {
                            addingWalletFromHome = true
                            navController.navigate(MeshNavRoutes.CreateLaunch)
                        },
                        onAddExistingWallet = {
                            addingWalletFromHome = true
                            navController.navigate(MeshNavRoutes.AddExisting)
                        },
                        onWalletRemoved = {
                            navController.navigate(MeshNavRoutes.Welcome) {
                                popUpTo(MeshNavRoutes.Home) { inclusive = true }
                            }
                        }
                    )
                }
            }
        }

        if (showBiometricBackdrop) {
            MeshSplashView()
        }

        if (didFinishLaunchRouting) {
            MeshEdgeDismissWrapper(visible = homeOverlay == HomeOverlay.Send, onDismiss = { homeOverlay = HomeOverlay.None }, presentationEdge = PresentationEdge.Trailing) {
                SendFlowHost(viewModel = sendViewModel, onClose = { homeOverlay = HomeOverlay.None; homeViewModel.refreshWallet() })
            }
            MeshEdgeDismissWrapper(visible = homeOverlay == HomeOverlay.Receive, onDismiss = { homeOverlay = HomeOverlay.None }, presentationEdge = PresentationEdge.Trailing) {
                ReceiveScreen(session = session, onBack = { homeOverlay = HomeOverlay.None })
            }
            MeshEdgeDismissWrapper(visible = homeOverlay == HomeOverlay.Security, onDismiss = { homeOverlay = HomeOverlay.None }, presentationEdge = PresentationEdge.Trailing) {
                WalletSecurityScreen(session = session, onBack = { homeOverlay = HomeOverlay.None }, onWalletRemoved = {
                    homeOverlay = HomeOverlay.None
                    navController.navigate(MeshNavRoutes.Welcome) { popUpTo(MeshNavRoutes.Home) { inclusive = true } }
                })
            }
            MeshEdgeDismissWrapper(visible = homeOverlay == HomeOverlay.Privacy, onDismiss = { homeOverlay = HomeOverlay.None }, presentationEdge = PresentationEdge.Leading) {
                WalletPrivacyScreen(session = session, onBack = { homeOverlay = HomeOverlay.None })
            }
            TransactionDetailSheet(transaction = selectedTransaction, onDismiss = { selectedTransaction = null })
        }
    }
}

private fun completeWalletSetup(
    addingWalletFromHome: Boolean,
    navController: androidx.navigation.NavHostController,
    onboardingViewModel: OnboardingViewModel,
    session: WalletSession,
    homeViewModel: WalletHomeViewModel,
    onAddWalletDone: () -> Unit
) {
    onboardingViewModel.commitWallet()
    if (addingWalletFromHome) {
        finishAddWalletFromHome(navController, onboardingViewModel, session, homeViewModel, onAddWalletDone)
    } else {
        session.completeOnboarding()
        navController.navigate(MeshNavRoutes.WalletReady) {
            popUpTo(MeshNavRoutes.Welcome) { inclusive = false }
        }
    }
}

private fun finishAddWalletFromHome(
    navController: androidx.navigation.NavHostController,
    viewModel: OnboardingViewModel,
    session: WalletSession,
    homeViewModel: WalletHomeViewModel,
    onDone: () -> Unit
) {
    viewModel.commitWallet()
    session.reconcile()
    session.registry.wallets.lastOrNull()?.id?.let { session.setActiveWallet(it) }
    homeViewModel.refreshWallet()
    onDone()
    navController.navigate(MeshNavRoutes.Home) {
        popUpTo(MeshNavRoutes.Home) { inclusive = false }
    }
}
