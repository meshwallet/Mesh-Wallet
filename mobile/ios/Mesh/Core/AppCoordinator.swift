import Combine
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    enum Route: Equatable {
        case onboarding(OnboardingStartPoint)
        case wallet
    }

    @Published private(set) var route: Route

    init() {
        WalletSession.reconcile()
        route = WalletSession.hasActiveWallet ? .wallet : .onboarding(.welcome)
    }

    func refreshRoute() {
        WalletSession.reconcile()
        let next: Route = WalletSession.hasActiveWallet ? .wallet : .onboarding(.welcome)
        guard next != route else { return }
        route = next
    }

    func completeOnboarding() {
        WalletSession.markOnboardingComplete()
        WalletSession.reconcile()
        route = WalletSession.hasActiveWallet ? .wallet : .onboarding(.welcome)
    }

    func openOnboarding(from start: OnboardingStartPoint) {
        route = .onboarding(start)
    }

    func returnToWallet() {
        WalletSession.reconcile()
        route = WalletSession.hasActiveWallet ? .wallet : .onboarding(.welcome)
    }
}
