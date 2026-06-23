import Combine
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class ReceiveViewModel: ObservableObject {
    @Published var walletAddress = ""
    @Published var receiveAccountIndex: UInt32 = 0
    @Published var paymentIndex = 1
    @Published var isPrivateReceiveAddress = false
    @Published var receiveSlots: [WalletReceiveSlotOption] = []
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var didCopyAddress = false
    @Published var qrRefreshID = UUID()

    var captionText: String {
        guard let slot = receiveSlots.first(where: { $0.index == receiveAccountIndex }) else {
            return L10n.Receive.mainAddress
        }
        if slot.index == 0 {
            return L10n.Receive.mainAddress
        }
        return slot.title
    }

    var selectedReceiveSlot: WalletReceiveSlotOption? {
        receiveSlots.first { $0.index == receiveAccountIndex }
    }

    var displayAddress: String {
        Self.receiveDisplayAddress(walletAddress)
    }

    var shareText: String {
        """
        USDT (TRC-20) on Tron
        \(walletAddress)

        \(L10n.Receive.shareFooter)
        """
    }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let placeholders = try MeshPrivacyService.listWalletReceiveSlots()
            if !placeholders.isEmpty {
                withAnimation(MeshBalanceRevealAnimation.reveal) {
                    receiveSlots = placeholders
                }
            }

            let context = try MeshPrivacyService.prepareReceiveContext()
            apply(context)

            let slotsWithBalances = try await MeshPrivacyService.listWalletReceiveSlotsWithBalances()
            withAnimation(MeshBalanceRevealAnimation.reveal) {
                receiveSlots = slotsWithBalances
            }
            qrRefreshID = UUID()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func selectSlot(_ index: UInt32) {
        guard index != receiveAccountIndex else { return }
        do {
            let context = try MeshPrivacyService.selectReceiveSlot(index)
            apply(context)
            qrRefreshID = UUID()
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } catch {
            loadError = error.localizedDescription
        }
    }

    func copyAddress() {
        #if canImport(UIKit)
        UIPasteboard.general.string = walletAddress
        #endif
        didCopyAddress = true
    }

    private func apply(_ context: PrivacyReceiveContext) {
        walletAddress = context.address
        receiveAccountIndex = context.accountIndex
        paymentIndex = context.paymentNumber
        isPrivateReceiveAddress = context.isPrivateMode
    }

    static func receiveDisplayAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 16 else { return trimmed }
        let start = trimmed.prefix(5)
        let end = trimmed.suffix(9)
        return "\(start)...\(end)"
    }
}
