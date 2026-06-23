//
//  ContentView.swift
//  Mesh
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appLock: AppLockController
    @EnvironmentObject private var languageStore: MeshLanguageStore
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var appStoreUpdateChecker = MeshAppStoreUpdateChecker()
    @State private var didConfigureSDKs = false
    @State private var showSplash = true
    @State private var showLaunchBiometricBackdrop = false

    var body: some View {
        ZStack {
            if showLaunchBiometricBackdrop {
                MeshTheme.Colors.background.ignoresSafeArea()
            } else if showSplash {
                MeshSplashView()
            } else {
                ZStack {
                    if !showsLaunchPasscode {
                        mainRouteContent
                    }
                    if showsLaunchPasscode {
                        AppLockView {
                            appLock.unlock()
                        }
                        .zIndex(1)
                    }
                }
            }
        }
        .background(MeshTheme.Colors.background.ignoresSafeArea())
        .onAppear(perform: syncPrivacyShieldSuppression)
        .onChange(of: showSplash) { _, _ in syncPrivacyShieldSuppression() }
        .onChange(of: showLaunchBiometricBackdrop) { _, _ in syncPrivacyShieldSuppression() }
        .onChange(of: showsLaunchPasscode) { _, needsLock in
            if needsLock {
                WalletHomePreloader.startWarmIfNeeded()
            }
        }
        .task {
            guard !didConfigureSDKs else { return }
            didConfigureSDKs = true
            async let updateCheck: Void = appStoreUpdateChecker.checkOnLaunchIfNeeded()
            if showSplash {
                finishSplash()
            }
            _ = await updateCheck
            presentUpdateAlertIfReady()
        }
        .onChange(of: showSplash) { _, _ in presentUpdateAlertIfReady() }
        .onChange(of: showLaunchBiometricBackdrop) { _, _ in presentUpdateAlertIfReady() }
        .onChange(of: showsLaunchPasscode) { _, _ in presentUpdateAlertIfReady() }
        .alert(L10n.AppUpdate.title, isPresented: $appStoreUpdateChecker.showUpdateAlert) {
            Button(L10n.AppUpdate.update) {
                appStoreUpdateChecker.openAppStore()
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            if let version = appStoreUpdateChecker.updateOffer?.storeVersion {
                Text(L10n.AppUpdate.message(version))
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                #if canImport(UIKit)
                MeshPrivacyShield.hasBeenActive = true
                MeshPrivacyShield.dismiss()
                #endif
            case .background:
                Task { @MainActor in
                    MeshBackgroundSendService.shared.prepareForBackgroundContinuation()
                }
            case .inactive:
                #if canImport(UIKit)
                MeshPrivacyShield.presentIfAllowed()
                Task { @MainActor in
                    MeshBackgroundSendService.shared.prepareForBackgroundContinuation()
                }
                #endif
            @unknown default:
                break
            }
        }
        .tint(MeshTheme.Colors.accent)
        .preferredColorScheme(.dark)
        .environment(\.locale, languageStore.locale)
        .environment(\.layoutDirection, languageStore.selected.usesRightToLeftLayout ? .rightToLeft : .leftToRight)
        .id(languageStore.localeIdentifier)
    }

    private var showsLaunchPasscode: Bool {
        guard appLock.shouldShowLock else { return false }
        if case .wallet = coordinator.route { return true }
        return false
    }

    @ViewBuilder
    private var mainRouteContent: some View {
        switch coordinator.route {
        case .onboarding(let start):
            OnboardingFlowView(
                startPoint: start,
                onFinished: finishOnboarding,
                onCancelFromRoot: start == .welcome ? nil : { coordinator.returnToWallet() }
            )
        case .wallet:
            WalletHomeView()
                .environmentObject(coordinator)
                .environmentObject(appLock)
        }
    }

    private func finishSplash() {
        let needsWalletLock = MeshPasscodeStore.isEnabled
            && WalletSession.hasActiveWallet
            && !appLock.isUnlocked
        let canLaunchBiometric = MeshPasscodeStore.isBiometricEnabled
            && MeshBiometricAuth.isAvailable

        if needsWalletLock {
            WalletHomePreloader.startWarmIfNeeded()
        }

        guard needsWalletLock, canLaunchBiometric else {
            showSplash = false
            return
        }

        Task { @MainActor in
            showLaunchBiometricBackdrop = true
            await appLock.attemptLaunchBiometricUnlock()
            showLaunchBiometricBackdrop = false
            showSplash = false
        }
    }

    private func finishOnboarding() {
        coordinator.completeOnboarding()
        if MeshPasscodeStore.isEnabled {
            appLock.unlockForCurrentSession()
        }
    }

    private func syncPrivacyShieldSuppression() {
        #if canImport(UIKit)
        MeshPrivacyShield.isSuppressed = showSplash || showLaunchBiometricBackdrop
        #endif
    }

    private func presentUpdateAlertIfReady() {
        guard !showSplash, !showLaunchBiometricBackdrop, !showsLaunchPasscode else { return }
        appStoreUpdateChecker.presentUpdateAlertIfReady()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppLockController())
        .environmentObject(MeshLanguageStore.shared)
}
