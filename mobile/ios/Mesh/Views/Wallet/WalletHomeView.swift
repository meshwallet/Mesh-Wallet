import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WalletHomeView: View {
    private enum PendingWalletSheetAction {
        case addExisting
        case createNew
    }

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var appLock: AppLockController
    @ObservedObject private var viewModel = WalletHomePreloader.viewModel
    @ObservedObject private var backgroundSend = MeshBackgroundSendService.shared
    @ObservedObject private var deepRecovery = MeshDeepRecoveryService.shared
    @State private var balanceHidden = false
    @State private var showSendFlow = false
    @State private var showReceiveFlow = false
    @State private var showPrivacy = false
    @State private var showSecurity = false
    @State private var showWalletPicker = false
    @State private var pendingWalletSheetAction: PendingWalletSheetAction?
    @State private var showAddExistingFlow = false
    @State private var showCreateWalletFlow = false
    @StateObject private var createWalletFlowModel = WalletCreateFlowModel()
    @StateObject private var sendFlowBinding = SendFlowBinding()
    @State private var selectedTransaction: WalletTransaction?
    @State private var selectedWalletID = MeshWalletRegistry.activeWalletID ?? WalletAccountStore.mainWalletID
    @State private var walletListRevision = 0
    @State private var activityFilter: WalletActivityFilter = .all
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportHeight: CGFloat = 800
    @State private var receiveSlotPendingDeletion: UInt32?
    @State private var receiveSlotPendingRename: UInt32?
    @State private var showReceiveSlotRenameAlert = false
    @State private var renameReceiveSlotDraft = ""
    @State private var showReceiveSlotDeleteAlert = false
    @State private var showCreateBalanceNameAlert = false
    @State private var createBalanceNameDraft = ""
    @State private var isHomeReceiveSlotExpanded = false
    @State private var showAddressDrawer = false
    @State private var didFinishInitialHomeTask = false

    private static let balancePollIntervalNanoseconds: UInt64 = 15_000_000_000

    private let expandedBalanceFontSize = MeshTheme.Metrics.walletHomeBalanceExpandedSize
    private let collapsedBalanceFontSize = MeshTheme.Metrics.walletHomeBalanceCollapsedSize
    private let balanceFontMinScale: CGFloat = 0.38
    private let expandedUSDTFontSize: CGFloat = 24
    private let collapsedUSDTFontSize: CGFloat = 15
    private let collapsedHeroHeightDefault: CGFloat = 152
    private let collapsedHeroHeightWithSlots: CGFloat = 200
    private let homeHeaderSingleLineHeight: CGFloat = 44
    private let homeHeaderMultiAccountHeight: CGFloat = 58
    private let homeHeaderTotalAmountRowHeight: CGFloat = 14
    private let homeSlotsTopSpacing: CGFloat = 8

    private var homeSlotsLayoutToken: String {
        "\(viewModel.receiveSlotBalances.count)-\(viewModel.focusedReceiveSlotIndex)-\(viewModel.canAddHomeReceiveAddress)-\(isHomeReceiveSlotExpanded)"
    }

    private func homeAddressListMaxExpandedHeight(collapseProgress: CGFloat) -> CGFloat {
        let topInset = homeSlotsSectionTopInset(collapseProgress: collapseProgress)
        let bottomReserve = heroBottomChromeHeight + 12
        let addFooter: CGFloat = viewModel.canAddHomeReceiveAddress ? 52 : 0
        let sectionSpacing: CGFloat = 10
        return max(120, heroHeight - topInset - bottomReserve - addFooter - sectionSpacing)
    }

    private func homeSlotsStackHeight(collapseProgress: CGFloat) -> CGFloat {
        let maxExpanded = homeAddressListMaxExpandedHeight(collapseProgress: collapseProgress)
        let expanded = MeshWalletSlotPickerView.preferredHeight(
            slotCount: viewModel.receiveSlotBalances.count,
            isExpanded: isHomeReceiveSlotExpanded,
            includesAddFooter: viewModel.canAddHomeReceiveAddress,
            showsHeader: false,
            maxExpandedListHeight: maxExpanded
        )
        let collapsed = MeshWalletSlotPickerView.preferredHeight(
            slotCount: viewModel.receiveSlotBalances.count,
            isExpanded: false,
            includesAddFooter: false,
            showsHeader: false
        ) + 6
        let progress = min(max(collapseProgress, 0), 1)
        return expanded - progress * (expanded - collapsed)
    }

    private var usesSlotBalanceHero: Bool {
        false
    }
    private let headerChromeIconSize: CGFloat = 40
    private let headerMenuIconSize: CGFloat = 32
    private let headerMenuTapWidth: CGFloat = 56
    private let expandedHeroViewportFraction: CGFloat = 0.66
    /// Small gap between hero bottom and first section header (not scroll dead zone).
    private let transactionsClearanceBelowHero: CGFloat = 8

    private var collapsedHeroHeight: CGFloat {
        usesSlotBalanceHero ? collapsedHeroHeightWithSlots : collapsedHeroHeightDefault
    }

    private var expandedHeroHeight: CGFloat {
        max(viewportHeight * expandedHeroViewportFraction, collapsedHeroHeight + 8)
    }

    private var collapseDistance: CGFloat {
        max(120, expandedHeroHeight - collapsedHeroHeight)
    }

    private let scrollBottomBreathingRoom: CGFloat = 4

    /// Tall enough scroll content to complete hero collapse.
    private var scrollContentMinHeight: CGFloat {
        viewportHeight + collapseDistance + 1
    }

    /// Bottom slack — room to finish collapsing the hero after the last row.
    private var scrollCollapseBottomSlack: CGFloat {
        collapseDistance + scrollBottomBreathingRoom
    }

    /// Scrollable body below the hero spacer (excludes fund-button overlay padding).
    private var scrollableBodyHeight: CGFloat {
        transactionsSectionHeight
    }

    /// How far the user can scroll before the hero is fully collapsed.
    /// Uses expanded hero height only — must not read `scrollHeroSpacerHeight` / `heroHeight`
    /// (those depend on `collapseProgress`, which depends on this range → stack overflow).
    private var heroCollapseScrollRange: CGFloat {
        max(
            collapseDistance,
            expandedHeroHeight
                + transactionsClearanceBelowHero
                + scrollableBodyHeight
                + scrollCollapseBottomSlack
                - viewportHeight
        )
    }

    private var collapseProgress: CGFloat {
        guard collapseDistance > 0, heroCollapseScrollRange > 0 else { return 0 }
        let effectiveDistance = min(collapseDistance, heroCollapseScrollRange)
        return min(1, max(0, scrollOffset / effectiveDistance))
    }

    private var transactionsSectionHeight: CGFloat {
        if viewModel.transactions.isEmpty {
            return 128
        }
        if filteredTransactions.isEmpty {
            return 80
        }
        var height: CGFloat = 0
        for group in groupedTransactions {
            height += 28
            height += CGFloat(group.items.count) * 60
        }
        height += CGFloat(max(0, groupedTransactions.count - 1)) * 8
        if viewModel.loadError != nil {
            height += 44
        }
        return height
    }

    private var heroHeight: CGFloat {
        expandedHeroHeight - collapseProgress * (expandedHeroHeight - collapsedHeroHeight)
    }

    private var balanceFontSize: CGFloat {
        expandedBalanceFontSize + (collapsedBalanceFontSize - expandedBalanceFontSize) * collapseProgress
    }

    private func fittedBalanceAmountFontSize(
        rowWidth: CGFloat,
        baseAmountSize: CGFloat,
        usdtSize: CGFloat,
        eyeIconSize: CGFloat,
        rowSpacing: CGFloat,
        amountUSDTSpacing: CGFloat
    ) -> CGFloat {
        let innerWidth = max(0, rowWidth - MeshTheme.Metrics.screenPadding * 2)
        let usdtReserve = MeshBalanceFontFit.measureWidth(" USDT", fontSize: usdtSize, weight: .light)
            + amountUSDTSpacing
        let eyeReserve = eyeIconSize + rowSpacing
        let amountMaxWidth = max(0, innerWidth - usdtReserve - eyeReserve)
        return MeshBalanceFontFit.fittedFontSize(
            text: viewModel.heroFormattedBalance,
            baseSize: baseAmountSize,
            maxWidth: amountMaxWidth,
            minScale: balanceFontMinScale
        )
    }

    private var usdtFontSize: CGFloat {
        expandedUSDTFontSize + (collapsedUSDTFontSize - expandedUSDTFontSize) * collapseProgress
    }

    private var sendReceiveVisibility: CGFloat {
        max(0, 1 - smoothstep(edge0: 0.18, edge1: 0.44, x: collapseProgress))
    }

    private var filterProgress: CGFloat {
        if usesSlotBalanceHero {
            return smoothstep(edge0: 0.52, edge1: 0.84, x: collapseProgress)
        }
        if viewModel.showsHomeAccountCaption {
            // Fade filters in only after the account caption has cleared the bottom chrome.
            return smoothstep(edge0: 0.56, edge1: 0.88, x: collapseProgress)
        }
        return smoothstep(edge0: 0.40, edge1: 0.72, x: collapseProgress)
    }

    /// "Main" / account label under balance — hide before filter bar overlaps it.
    private var accountCaptionOpacity: CGFloat {
        guard viewModel.showsHomeAccountCaption else { return 0 }
        return max(0, 1 - smoothstep(edge0: 0.30, edge1: 0.50, x: collapseProgress))
    }

    private var homeAccountCaptionBottomInset: CGFloat {
        guard viewModel.showsHomeAccountCaption else { return 0 }
        return filterChromeHeight * filterProgress + 10 * collapseProgress
    }

    private let heroFilterBarHeight: CGFloat = 48
    private let heroFilterBarVerticalPadding: CGFloat = 6
    private let heroSendReceiveBottomPadding: CGFloat = 36
    private let sendReceiveRowHeight: CGFloat = 100

    private var sendReceiveChromeHeight: CGFloat {
        sendReceiveRowHeight + heroSendReceiveBottomPadding
    }

    private var filterChromeHeight: CGFloat {
        heroFilterBarHeight + heroFilterBarVerticalPadding * 2
    }

    /// Shrinks with hero collapse so filter sits under balance without a dead zone.
    private var heroBottomChromeHeight: CGFloat {
        sendReceiveChromeHeight + (filterChromeHeight - sendReceiveChromeHeight) * collapseProgress
    }

    private var balancePollTrigger: String {
        "\(selectedWalletID)-\(scenePhase)"
    }

    private var showsEmptyFundButton: Bool {
        didFinishInitialHomeTask
            && !viewModel.isLoading
            && !viewModel.isHistoryLoading
            && viewModel.transactions.isEmpty
    }

    private var canSend: Bool {
        viewModel.usdtBalance > 0
    }

    private var addressDrawerIconTopPadding: CGFloat {
        4 + (homeHeaderRowHeight - headerMenuIconSize) / 2
    }

    private func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x >= edge1 ? 1 : 0 }
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        GeometryReader { geometry in
            let drawerLeadingInset = MeshWalletAddressDrawer.screenLeadingInset
            let drawerPanelWidth = geometry.size.width * MeshWalletAddressDrawer.widthRatio
            let drawerTravel = drawerPanelWidth + drawerLeadingInset
            let drawerX = showAddressDrawer ? drawerLeadingInset : -drawerTravel

            ZStack(alignment: .topLeading) {
                ZStack {
                    homeContent

                    if showSendFlow {
                        MeshEdgeDismissWrapper(isPresented: $showSendFlow) {
                            SendFlowView(
                                model: sendFlowBinding.model,
                                sendFlowBinding: sendFlowBinding,
                                initialSpendableUSDT: viewModel.usdtBalance,
                                initialBalanceIsKnown: viewModel.usdtBalance > 0 || !viewModel.isBalanceLoading
                            )
                        }
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                    }

                    if showReceiveFlow {
                        MeshEdgeDismissWrapper(isPresented: $showReceiveFlow) {
                            ReceiveUSDTView()
                        }
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                    }

                    if showPrivacy {
                        MeshEdgeDismissWrapper(isPresented: $showPrivacy, presentationEdge: .leading) {
                            WalletPrivacyView()
                        }
                        .transition(.move(edge: .leading))
                        .zIndex(1)
                    }

                    if showSecurity {
                        MeshEdgeDismissWrapper(isPresented: $showSecurity) {
                            WalletSecurityView()
                                .environmentObject(coordinator)
                                .environmentObject(MeshLanguageStore.shared)
                        }
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                    }
                }

                Color.black
                    .opacity(showAddressDrawer ? 0.32 : 0)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissAddressDrawer() }
                    .allowsHitTesting(showAddressDrawer)
                    .zIndex(2)

                addressDrawerContent(panelWidth: drawerPanelWidth)
                    .offset(x: drawerX)
                    .allowsHitTesting(showAddressDrawer)
                    .zIndex(3)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showAddressDrawer)
        }
        .task(id: showAddressDrawer) {
            guard showAddressDrawer else { return }
            await viewModel.refreshReceiveSlotsIfNeeded()
        }
        .fullScreenCover(isPresented: $showAddExistingFlow, onDismiss: resetWalletFlowSession) {
            OnboardingFlowView(
                startPoint: .addExisting,
                onFinished: {
                    showAddExistingFlow = false
                    handleWalletAddedFromFlow()
                },
                onCancelFromRoot: {
                    showAddExistingFlow = false
                }
            )
        }
        .fullScreenCover(isPresented: $showCreateWalletFlow, onDismiss: resetWalletFlowSession) {
            WalletCreateFlowHost(
                flowModel: createWalletFlowModel,
                onFinished: {
                    showCreateWalletFlow = false
                    handleWalletAddedFromFlow()
                },
                onCancel: {
                    showCreateWalletFlow = false
                }
            )
        }
        .sheet(item: $selectedTransaction) { transaction in
            WalletTransactionDetailView(transaction: transaction) {
                selectedTransaction = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground {
                MeshSelectWalletSheetBackground()
            }
        }
        .sheet(isPresented: $showWalletPicker, onDismiss: handleWalletPickerDismissed) {
            SelectWalletSheet(
                accounts: WalletAccountStore.activeAccounts(),
                selectedAccountID: selectedWalletID,
                onSelect: { walletID in
                    selectedWalletID = walletID
                    WalletSession.setActiveWallet(id: walletID)
                    viewModel.prepareForWallet(id: walletID)
                },
                onWalletRenamed: {
                    walletListRevision += 1
                },
                onWalletRemoved: { deletedWalletID in
                    syncSelectedWalletFromRegistry(deletedWalletID: deletedWalletID)
                    if WalletSession.hasActiveWallet {
                        Task { await viewModel.load(transactionLimit: 24) }
                    } else {
                        showWalletPicker = false
                        coordinator.refreshRoute()
                    }
                },
                onAddExisting: {
                    pendingWalletSheetAction = .addExisting
                },
                onCreateNew: {
                    pendingWalletSheetAction = .createNew
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground {
                MeshSelectWalletSheetBackground()
            }
        }
        .onChange(of: showReceiveFlow) { _, isShowing in
            if isShowing {
            } else {
                viewModel.applyFocusedSlotFromStoreIfNeeded()
            }
        }
        .onChange(of: showSendFlow) { _, isShowing in
            if !isShowing { viewModel.applyFocusedSlotFromStoreIfNeeded() }
        }
        .onChange(of: selectedWalletID) { _, walletID in
            sendFlowBinding.bind(walletID: walletID)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: showSendFlow)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: showReceiveFlow)
        // .animation(.spring(response: 0.42, dampingFraction: 0.9), value: showPrivacy)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: showSecurity)
        .alert(
            L10n.WalletAddressDrawer.createBalanceTitle,
            isPresented: $showCreateBalanceNameAlert
        ) {
            TextField(L10n.WalletAddressDrawer.createBalancePlaceholder, text: $createBalanceNameDraft)
            Button(L10n.WalletAddressDrawer.createBalanceAction) {
                let name = createBalanceNameDraft
                createBalanceNameDraft = ""
                Task { await viewModel.addHomeReceiveAddress(customName: name) }
            }
            Button(L10n.Common.cancel, role: .cancel) {
                createBalanceNameDraft = ""
            }
        }
        .modifier(HomeReceiveSlotRenameAlertModifier(
            isPresented: $showReceiveSlotRenameAlert,
            slotIndex: receiveSlotPendingRename,
            name: $renameReceiveSlotDraft,
            onSave: { index, name in
                viewModel.renameHomeReceiveAccount(at: index, name: name)
                renameReceiveSlotDraft = ""
                receiveSlotPendingRename = nil
            },
            onCancel: {
                renameReceiveSlotDraft = ""
                receiveSlotPendingRename = nil
            }
        ))
        .alert(
            L10n.Receive.deleteAddressTitle,
            isPresented: $showReceiveSlotDeleteAlert,
            presenting: receiveSlotPendingDeletion
        ) { index in
            Button(L10n.Receive.deleteAddressAction, role: .destructive) {
                Task {
                    await viewModel.removeHomeReceiveAddress(at: index)
                    receiveSlotPendingDeletion = nil
                }
            }
            Button(L10n.Common.cancel, role: .cancel) {
                receiveSlotPendingDeletion = nil
            }
        } message: { index in
            Text(viewModel.receiveSlotDeleteAlertMessage(for: index))
        }
        .preferredColorScheme(.dark)
    }

    private func resetWalletFlowSession() {
        MeshWalletCreationGate.reset()
        createWalletFlowModel.reset()
    }

    private func handleWalletPickerDismissed() {
        guard let action = pendingWalletSheetAction else { return }
        pendingWalletSheetAction = nil
        switch action {
        case .addExisting:
            presentWalletFlow { showAddExistingFlow = true }
        case .createNew:
            presentWalletFlow { showCreateWalletFlow = true }
        }
    }

    private func handleWalletAddedFromFlow() {
        WalletSession.markOnboardingComplete()
        WalletSession.reconcile()
        syncSelectedWalletFromRegistry()
        if MeshPasscodeStore.isEnabled {
            appLock.unlockForCurrentSession()
        }
        Task { await viewModel.load(transactionLimit: 24) }
    }

    private func dismissAddressDrawer() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            showAddressDrawer = false
        }
    }

    private func presentWalletFlow(_ present: () -> Void) {
        showAddressDrawer = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
            present()
        }
    }

    @ViewBuilder
    private func addressDrawerContent(panelWidth: CGFloat) -> some View {
        MeshWalletAddressDrawer(
            isPresented: $showAddressDrawer,
            balanceHidden: $balanceHidden,
            panelWidth: panelWidth,
            panelTopInset: 0,
            headerTopPadding: addressDrawerIconTopPadding,
            headerRowHeight: homeHeaderRowHeight,
            subaccountsIconSize: headerMenuIconSize,
            slots: viewModel.receiveSlotBalancesForDisplay,
            selectedIndex: viewModel.focusedReceiveSlotIndex,
            canAdd: viewModel.canAddHomeReceiveAddress,
            isLoading: viewModel.isBalanceLoading || viewModel.isPullRefreshing,
            onSelect: { index in
                viewModel.selectHomeReceiveSlot(index, animated: false)
            },
            onAdd: {
                presentCreateBalanceNameAlert()
            },
            onRename: { index in
                receiveSlotPendingRename = index
                renameReceiveSlotDraft = viewModel.receiveSlotRenameDraft(for: index)
                showReceiveSlotRenameAlert = true
            },
            onDelete: { index in
                receiveSlotPendingDeletion = index
                showReceiveSlotDeleteAlert = true
            }
        )
    }

    private func syncSelectedWalletFromRegistry(deletedWalletID: String? = nil) {
        walletListRevision += 1

        if let deletedWalletID {
            viewModel.purgeWalletCache(id: deletedWalletID)
            WalletHomePreloader.invalidate(forWalletID: deletedWalletID)
        }

        guard let active = MeshWalletRegistry.activeWalletID else {
            coordinator.refreshRoute()
            return
        }

        if selectedWalletID != active {
            WalletHomePreloader.invalidate()
        }
        viewModel.prepareForWallet(id: active)
        if selectedWalletID != active {
            selectedWalletID = active
        }
    }

    // MARK: - Layout

    private var homeContent: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top

            ZStack(alignment: .bottom) {
                MeshWalletHomeColors.bottomSurface
                    .ignoresSafeArea()

                ZStack(alignment: .top) {
                    transactionsScrollView
                        .zIndex(0)

                    heroOverlay(topInset: topInset)
                        .zIndex(1)
                }

                if showsEmptyFundButton {
                    fundWalletButton
                }
            }
            .onAppear {
                let height = proxy.size.height
                guard height.isFinite, height > 0, abs(viewportHeight - height) > 0.5 else { return }
                viewportHeight = height
            }
            .onChange(of: proxy.size.height) { _, height in
                guard height.isFinite, height > 0, abs(viewportHeight - height) > 0.5 else { return }
                viewportHeight = height
            }
        }
        .onAppear {
            if let active = MeshWalletRegistry.activeWalletID, selectedWalletID != active {
                selectedWalletID = active
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshActiveWalletDidChange)) { notification in
            let deletedID = notification.userInfo?[MeshWalletRegistry.deletedWalletIDUserInfoKey] as? String
            syncSelectedWalletFromRegistry(deletedWalletID: deletedID)
            viewModel.preloadAllWalletBalances()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meshWalletBalancesShouldRefresh)) { _ in
            guard WalletSession.hasActiveWallet, didFinishInitialHomeTask else { return }
            guard !showSendFlow, !showReceiveFlow, !showPrivacy, !showSecurity else { return }
            guard !viewModel.isLoading, !viewModel.isPullRefreshing else { return }
            Task { await viewModel.refreshBalance() }
        }
        .task(id: selectedWalletID) {
            guard WalletSession.hasActiveWallet else {
                coordinator.refreshRoute()
                return
            }
            didFinishInitialHomeTask = false
            await Task.yield()
            WalletHomePreloader.startWarmIfNeeded()
            await WalletHomePreloader.awaitWarmIfNeeded()
            viewModel.prepareForWallet(id: selectedWalletID)
            if viewModel.transactions.isEmpty {
                await viewModel.load(transactionLimit: 24)
            }
            didFinishInitialHomeTask = true
            viewModel.preloadAllWalletBalances()
        }
        .task(id: balancePollTrigger) {
            guard scenePhase == .active, WalletSession.hasActiveWallet else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.balancePollIntervalNanoseconds)
                guard !Task.isCancelled, scenePhase == .active, WalletSession.hasActiveWallet else { continue }
                guard !showSendFlow, !showReceiveFlow, !showPrivacy, !showSecurity else { continue }
                if backgroundSend.needsHistoryReconcile {
                    await viewModel.load(transactionLimit: 24)
                } else {
                    await viewModel.refreshBalance()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, WalletSession.hasActiveWallet, didFinishInitialHomeTask else { return }
            guard !showSendFlow, !showReceiveFlow else { return }
            Task { await viewModel.refreshBalance() }
        }
        .onChange(of: backgroundSend.shouldRefreshWalletHistory) { shouldRefresh in
            guard shouldRefresh, WalletSession.hasActiveWallet else { return }
            Task {
                await viewModel.load(transactionLimit: 24)
                backgroundSend.acknowledgeHistoryRefresh()
            }
        }
        .onReceive(backgroundSend.$trackedTransfers) { _ in
            viewModel.mergePendingFromBackgroundSend()
        }
    }

    private func heroOverlay(topInset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            MeshWalletHomeHeroBackdrop(height: heroHeight + topInset)
            MeshWalletHomeHeroScrollFade(height: heroHeight + topInset)

            collapsibleHeroContent
                .frame(height: heroHeight, alignment: .top)

            heroInteractionOverlay
                .frame(height: heroHeight, alignment: .top)
                .clipped()
        }
        .frame(height: heroHeight + topInset, alignment: .top)
        .offset(y: -topInset)
        .frame(maxWidth: .infinity)
    }

    /// Tappable chrome only — root is pass-through so drags reach ScrollView (pull-to-refresh, collapse).
    private var heroInteractionOverlay: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .overlay(alignment: .top) {
                header
                    .allowsHitTesting(true)
            }
            .overlay(alignment: .top) {
                if usesSlotBalanceHero {
                    homeStaticSlotsSection(collapseProgress: collapseProgress)
                        .allowsHitTesting(true)
                }
            }
            .overlay(alignment: .bottom) {
                heroBottomChrome
            }
            .overlay(alignment: .topTrailing) {
                if usesSlotBalanceHero {
                    homeSlotsBalanceEyeButton(collapseProgress: collapseProgress)
                        .allowsHitTesting(true)
                }
            }
    }

    private var collapsibleHeroContent: some View {
        VStack(spacing: 0) {
            header
                .allowsHitTesting(false)

            Color.clear
                .frame(height: max(0, (1 - collapseProgress) * 20))
                .accessibilityHidden(true)
                .allowsHitTesting(false)

            if usesSlotBalanceHero {
                homeStaticSlotsPlaceholder(collapseProgress: collapseProgress)
                    .allowsHitTesting(false)
            } else {
                balanceSection(
                    amountSize: balanceFontSize,
                    usdtSize: usdtFontSize,
                    eyeIconSize: 16 - collapseProgress * 2,
                    layoutProgress: collapseProgress,
                    accountCaptionOpacity: accountCaptionOpacity,
                    bottomChromeInset: homeAccountCaptionBottomInset
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(nil, value: collapseProgress)
            }

            if deepRecovery.isRunning {
                deepRecoveryHomeBanner
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }

            Color.clear
                .frame(height: heroBottomChromeHeight)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(nil, value: viewModel.receiveSlotBalances.count)
    }

    private func homeStaticSlotsPlaceholder(collapseProgress: CGFloat) -> some View {
        Color.clear
            .frame(height: homeSlotsStackHeight(collapseProgress: collapseProgress))
            .animation(MeshBalanceRevealAnimation.listExpand, value: homeSlotsLayoutToken)
            .accessibilityHidden(true)
    }

    private func homeStaticSlotsSection(collapseProgress: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MeshWalletSlotPickerView(
                headerTitle: "",
                slots: viewModel.receiveSlotBalances,
                selectedIndex: viewModel.focusedReceiveSlotIndex,
                isExpanded: $isHomeReceiveSlotExpanded,
                showsHeader: false,
                isLoading: viewModel.isBalanceLoading || viewModel.isPullRefreshing,
                showsBalance: true,
                balanceHidden: balanceHidden,
                usesOpaqueCards: true,
                maxExpandedListHeight: homeAddressListMaxExpandedHeight(
                    collapseProgress: collapseProgress
                ),
                collapsedPresentation: .stackedPreview,
                onLongPress: { index in
                    receiveSlotPendingDeletion = index
                    showReceiveSlotDeleteAlert = true
                }
            ) { index in
                viewModel.selectHomeReceiveSlot(index)
            }

            if viewModel.canAddHomeReceiveAddress {
                homeAddReceiveAddressRow
            }
        }
        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
        .padding(.top, homeSlotsSectionTopInset(collapseProgress: collapseProgress))
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(MeshBalanceRevealAnimation.listExpand, value: isHomeReceiveSlotExpanded)
        .animation(MeshBalanceRevealAnimation.listExpand, value: homeSlotsLayoutToken)
    }

    private func presentCreateBalanceNameAlert() {
        createBalanceNameDraft = viewModel.suggestedNewBalanceName()
        showCreateBalanceNameAlert = true
    }

    private var homeAddReceiveAddressRow: some View {
        Button(action: presentCreateBalanceNameAlert) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                Text(L10n.Receive.generateAddress)
                    .font(MeshTheme.Typography.sans(size: 14, weight: .medium))
            }
            .foregroundStyle(MeshTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add address")
    }

    private func homeSlotsBalanceEyeButton(collapseProgress: CGFloat) -> some View {
        Group {
            if viewModel.isPullRefreshing {
                ProgressView()
                    .tint(MeshTheme.Colors.textSecondary)
            } else {
                Button(action: toggleBalanceVisibility) {
                    Image(systemName: balanceHidden ? "eye.slash" : "eye")
                        .font(MeshTheme.Typography.icon(size: 16, weight: .light))
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                        .frame(width: 44, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(balanceHidden ? "Show balance" : "Hide balance")
            }
        }
        .frame(width: 44, height: 40)
        .padding(.top, homeSlotsSectionTopInset(collapseProgress: collapseProgress) + 10)
        .padding(.trailing, MeshTheme.Metrics.screenPadding + 12)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isPullRefreshing)
    }

    /// Keeps the main address card clear of the header when the hero is collapsed.
    private func homeSlotsSectionTopInset(collapseProgress: CGFloat) -> CGFloat {
        homeHeaderRowHeight
            + homeSlotsTopSpacing
            + 14
            + max(0, (1 - collapseProgress) * 18)
    }

    /// Fixed-height bottom slot: Send/Receive fade out, filter fades in — height tracks collapse.
    private var heroBottomChrome: some View {
        Color.clear
            .frame(height: heroBottomChromeHeight)
            .allowsHitTesting(false)
            .overlay(alignment: .bottom) {
                if sendReceiveVisibility > 0.02 {
                    sendReceiveRow
                        .opacity(Double(sendReceiveVisibility))
                        .scaleEffect(0.84 + 0.16 * sendReceiveVisibility, anchor: .bottom)
                        .offset(y: 10 * (1 - sendReceiveVisibility))
                        .allowsHitTesting(sendReceiveVisibility > 0.35)
                        .accessibilityHidden(sendReceiveVisibility < 0.05)
                        .padding(.bottom, heroSendReceiveBottomPadding)
                }
            }
            .overlay(alignment: .bottom) {
                if filterProgress > 0.02 {
                    WalletActivityFilterBar(
                        selection: $activityFilter,
                        style: .pill
                    )
                    .frame(height: heroFilterBarHeight)
                    .opacity(Double(filterProgress))
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.bottom, heroFilterBarVerticalPadding)
                    .allowsHitTesting(filterProgress > 0.35)
                    .accessibilityHidden(filterProgress < 0.05)
                }
            }
            .animation(nil, value: filterProgress)
            .animation(nil, value: sendReceiveVisibility)
            .animation(nil, value: collapseProgress)
    }

    private var transactionsScrollView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if #unavailable(iOS 18.0) {
                    WalletHomeScrollOffsetProbe(offset: $scrollOffset)
                }

                Color.clear
                    .frame(height: scrollHeroSpacerHeight)
                    .animation(
                        usesSlotBalanceHero ? MeshBalanceRevealAnimation.listExpand : nil,
                        value: homeSlotsLayoutToken
                    )
                    .accessibilityHidden(true)

                transactionsContent

                Color.clear
                    .frame(height: scrollCollapseBottomSlack)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: scrollContentMinHeight, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .background(MeshWalletHomeColors.bottomSurface)
        .walletHomeScrollContentTopAligned()
        .walletHomeScrollClipDisabled()
        .walletHomeTracksScrollOffset($scrollOffset)
        .scrollBounceBehavior(.always)
        .refreshable {
            guard WalletSession.hasActiveWallet else { return }
            await viewModel.pullToRefresh(transactionLimit: 24)
        }
        .walletHomeScrollBehavior()
    }

    /// Spacer tracks collapsing hero so the list starts below the filter, not under it.
    private var scrollHeroSpacerHeight: CGFloat {
        heroHeight + transactionsClearanceBelowHero
    }

    private var fundWalletButton: some View {
        MeshWalletFundButton(title: L10n.Wallet.fund) {
            presentWalletFlow { showReceiveFlow = true }
        }
        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
        .padding(.bottom, 12)
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    MeshWalletHomeColors.bottomVeil(0.88),
                    MeshWalletHomeColors.bottomSurface,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .offset(y: -40)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Header

    private var homeHeaderRowHeight: CGFloat {
        viewModel.supportsHomeAccountLayout ? homeHeaderMultiAccountHeight : homeHeaderSingleLineHeight
    }

    private var homeMultiAccountChromeOpacity: Double {
        viewModel.showsHomeMultiAccountChrome ? 1 : 0
    }

    private var homeHeroCaptionFont: Font {
        MeshTheme.Typography.sans(size: 11, weight: .light)
    }

    private var header: some View {
        Color.clear
            .frame(height: homeHeaderRowHeight)
            .allowsHitTesting(false)
            .overlay(alignment: .leading) {
                headerIconButton(
                    width: headerMenuTapWidth,
                    alignment: .leading
                ) {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        showAddressDrawer = true
                    }
                } label: {
                    Image("subaccounts")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: headerMenuIconSize, height: headerMenuIconSize)
                        .foregroundStyle(MeshTheme.Colors.homeChromeIcon)
                        .frame(width: headerMenuTapWidth, height: headerMenuTapWidth)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(L10n.WalletAddressDrawer.title)
            }
            .overlay(alignment: .trailing) {
                headerIconButton(
                    width: 48,
                    alignment: .trailing
                ) {
                    presentWalletFlow { showSecurity = true }
                } label: {
                    Image("gearshape")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: headerChromeIconSize, height: headerChromeIconSize)
                        .foregroundStyle(MeshTheme.Colors.homeChromeIcon)
                }
            }
            .overlay {
                Button { showWalletPicker = true } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Text(WalletAccountStore.activeAccountName())
                                .font(MeshTheme.Typography.sans(size: 17, weight: .medium))
                                .foregroundStyle(MeshTheme.Colors.homeTextPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                                .id(walletListRevision)

                            Image(systemName: "chevron.down")
                                .font(MeshTheme.Typography.icon(size: 12, weight: .semibold))
                                .foregroundStyle(MeshTheme.Colors.homeTextSecondary)
                        }

                        homeWalletTotalAmountCaption
                            .opacity(homeMultiAccountChromeOpacity)
                            .frame(height: homeHeaderTotalAmountRowHeight)
                            .animation(.easeInOut(duration: 0.28), value: homeMultiAccountChromeOpacity)
                            .accessibilityHidden(!viewModel.showsHomeMultiAccountChrome)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, headerMenuTapWidth)
                .padding(.trailing, 48)
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding - 8)
            .padding(.top, 4)
            .animation(nil, value: viewModel.receiveSlotBalances.count)
    }

    private var homeWalletTotalAmountCaption: some View {
        HStack(spacing: 4) {
            Text(L10n.Wallet.homeTotalAmountLabel)
                .font(homeHeroCaptionFont)
                .foregroundStyle(MeshTheme.Colors.textTertiary)

            Text("\(viewModel.formattedWalletTotalUSDT) USDT")
                .font(MeshTheme.Typography.sans(size: 11, weight: .semibold))
                .foregroundStyle(MeshTheme.Colors.textTertiary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .walletHomeBalancePrivacyBlur(
            isHidden: balanceHidden,
            visibleOpacity: viewModel.balanceDisplayOpacity,
            blurRadius: 4
        )
    }

    private var homeFocusedAccountCaption: some View {
        Text(viewModel.focusedAccountTitle)
            .font(homeHeroCaptionFont)
            .foregroundStyle(MeshTheme.Colors.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .walletHomeBalancePrivacyBlur(
                isHidden: balanceHidden,
                visibleOpacity: viewModel.balanceDisplayOpacity,
                blurRadius: 4
            )
            .animation(.easeInOut(duration: 0.28), value: balanceHidden)
    }

    // MARK: - Balance

    private func balanceSection(
        amountSize: CGFloat,
        usdtSize: CGFloat,
        eyeIconSize: CGFloat,
        layoutProgress: CGFloat,
        accountCaptionOpacity: CGFloat = 0,
        bottomChromeInset: CGFloat = 0
    ) -> some View {
        let rowSpacing = 10 + (8 - 10) * layoutProgress
        let minHeight = 80 + (36 - 80) * layoutProgress
        let amountUSDTSpacing = 6 + (5 - 6) * layoutProgress
        let refreshSpacing = 12 + (6 - 12) * layoutProgress

        return VStack(spacing: refreshSpacing) {
            if viewModel.isBalanceLoading, viewModel.usdtBalance == 0, !viewModel.isPullRefreshing {
                ProgressView()
                    .tint(MeshTheme.Colors.textSecondary)
                    .frame(minHeight: minHeight)
            } else {
                GeometryReader { geometry in
                let fittedAmountSize = fittedBalanceAmountFontSize(
                    rowWidth: geometry.size.width,
                    baseAmountSize: amountSize,
                    usdtSize: usdtSize,
                    eyeIconSize: eyeIconSize,
                    rowSpacing: rowSpacing,
                    amountUSDTSpacing: amountUSDTSpacing
                )

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: rowSpacing) {
                        balancePrivacyEyeButton(
                            eyeIconSize: eyeIconSize,
                            showsSpinner: viewModel.isPullRefreshing
                        )

                        Button(action: toggleBalanceVisibility) {
                            HStack(alignment: .firstTextBaseline, spacing: amountUSDTSpacing) {
                                balanceAmountLabel(
                                    fontSize: fittedAmountSize,
                                    usdtSize: usdtSize,
                                    layoutProgress: layoutProgress
                                )

                                Text("USDT")
                                    .font(MeshTheme.Typography.sans(size: usdtSize, weight: .light))
                                    .walletHomeBalanceSecondaryStyle()
                                    .walletHomeBalanceRefreshSettle(phase: viewModel.balanceSettlePhase)
                                    .walletHomeBalancePrivacyBlur(
                                        isHidden: balanceHidden,
                                        visibleOpacity: viewModel.balanceDisplayOpacity,
                                        blurRadius: 4
                                    )
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(balanceHidden ? "Show balance" : "Hide balance")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)

                    if viewModel.showsHomeAccountCaption, accountCaptionOpacity > 0.02 {
                        homeFocusedAccountCaption
                            .padding(.top, 1)
                            .offset(y: -5)
                            .opacity(Double(accountCaptionOpacity))
                            .accessibilityHidden(accountCaptionOpacity < 0.05)
                            .animation(.easeInOut(duration: 0.28), value: viewModel.focusedAccountTitle)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                .padding(.bottom, bottomChromeInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: minHeight)
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: minHeight)
        .animation(nil, value: accountCaptionOpacity)
        .animation(nil, value: bottomChromeInset)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: viewModel.balanceDisplayOpacity)
        .animation(.spring(response: 0.55, dampingFraction: 0.9), value: viewModel.balanceSettlePhase)
    }

    private func balancePrivacyEyeButton(eyeIconSize: CGFloat, showsSpinner: Bool) -> some View {
        Button(action: toggleBalanceVisibility) {
            Group {
                if showsSpinner {
                    ProgressView()
                        .tint(MeshTheme.Colors.textSecondary)
                } else {
                    Image(systemName: balanceHidden ? "eye.slash" : "eye")
                        .font(MeshTheme.Typography.icon(size: eyeIconSize, weight: .light))
                        .walletHomeBalanceSecondaryStyle()
                }
            }
            .walletHomeBalanceRefreshSettle(phase: viewModel.balanceSettlePhase)
            .opacity(balanceHidden ? 1 : viewModel.balanceDisplayOpacity)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(balanceHidden ? "Show balance" : "Hide balance")
    }

    private var deepRecoveryHomeBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                L10n.Send.deepRecoveryHomeBanner(
                    checked: deepRecovery.progressChecked,
                    total: deepRecovery.progressTotal
                )
            )
            .font(MeshTheme.Typography.caption())
            .foregroundStyle(MeshTheme.Colors.textSecondary)
            .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(MeshTheme.Colors.fieldFill.opacity(0.5))
                    Capsule()
                        .fill(MeshTheme.Colors.accent)
                        .frame(width: max(4, proxy.size.width * deepRecovery.progressFraction))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func balanceAmountLabel(fontSize: CGFloat, usdtSize: CGFloat, layoutProgress: CGFloat) -> some View {
        visibleBalanceText(fontSize: fontSize, usdtSize: usdtSize, layoutProgress: layoutProgress)
            .minimumScaleFactor(balanceFontMinScale)
            .allowsTightening(true)
            .walletHomeBalancePrivacyBlur(
                isHidden: balanceHidden,
                visibleOpacity: viewModel.balanceDisplayOpacity,
                blurRadius: 8
            )
            .animation(.easeInOut(duration: 0.28), value: balanceHidden)
    }

    private func toggleBalanceVisibility() {
        withAnimation(.easeInOut(duration: 0.28)) {
            balanceHidden.toggle()
        }
    }

    @ViewBuilder
    private func visibleBalanceText(fontSize: CGFloat, usdtSize: CGFloat, layoutProgress: CGFloat) -> some View {
        WalletHomeAnimatedBalanceText(
            text: viewModel.heroFormattedBalance,
            fontSize: fontSize,
            fractionalFontSize: usdtSize,
            hidden: balanceHidden,
            staleOpacity: viewModel.balanceDisplayOpacity,
            settlePhase: viewModel.balanceSettlePhase
        )
        .minimumScaleFactor(balanceFontMinScale)
    }

    // MARK: - Send / Receive

    private var sendReceiveRow: some View {
        HStack(spacing: 88) {
            MeshWalletCircleActionButton(
                icon: "arrow.down.left",
                title: L10n.Wallet.receive,
                action: { presentWalletFlow { showReceiveFlow = true } }
            )
            MeshWalletCircleActionButton(
                icon: "arrow.up.right",
                title: L10n.Wallet.send,
                isEnabled: canSend,
                action: { presentWalletFlow { showSendFlow = true } }
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
    }

    private func headerIconButton<Label: View>(
        width: CGFloat,
        alignment: Alignment,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let circleSize = MeshTheme.Metrics.circleButtonSize

        return Button(action: action) {
            label()
                .frame(width: circleSize, height: circleSize, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: max(width, circleSize), height: circleSize, alignment: alignment)
        .contentShape(Rectangle())
    }

    // MARK: - Transactions

    private var transactionsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if viewModel.isHistoryLoading && viewModel.transactions.isEmpty {
                    loadingState
                } else if viewModel.transactions.isEmpty {
                    emptyState
                } else if filteredTransactions.isEmpty {
                    filteredEmptyState
                } else {
                    transactionList
                }
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .padding(.bottom, showsEmptyFundButton ? 76 : 0)

            if let loadError = viewModel.loadError {
                Text(loadError)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(Color.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var filteredTransactions: [WalletTransaction] {
        let scoped = viewModel.transactions
        switch activityFilter {
        case .all:
            return scoped
        case .received:
            return scoped.filter(\.isIncoming)
        case .sent:
            return scoped.filter { !$0.isIncoming }
        }
    }

    private var transactionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groupedTransactions, id: \.day) { group in
                VStack(alignment: .leading, spacing: 0) {
                    MeshActivitySectionHeader(title: group.day, style: .home)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, tx in
                        Button {
                            selectedTransaction = tx
                        } label: {
                            WalletTransactionRowView(
                                transaction: tx,
                                balanceHidden: balanceHidden,
                                style: .home,
                                showsDivider: false,
                                showsDate: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var groupedTransactions: [(day: String, items: [WalletTransaction])] {
        filteredTransactions.groupedByDayLabel()
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(MeshTheme.Colors.textSecondary)
            Text("Loading transfers…")
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("WalletEmptyChart")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .opacity(0.55)

            Text("No transactions yet")
                .font(MeshTheme.Typography.sans(size: 16, weight: .regular))
                .foregroundStyle(MeshTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120)
        .padding(.top, 8)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Text("No \(activityFilter.title.lowercased()) transfers")
                .font(MeshTheme.Typography.body())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
            Text("Try another filter.")
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct HomeReceiveSlotRenameAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let slotIndex: UInt32?
    @Binding var name: String
    let onSave: (UInt32, String) -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            L10n.WalletAddressDrawer.renameAccountTitle,
            isPresented: $isPresented
        ) {
            TextField(L10n.WalletAddressDrawer.createBalancePlaceholder, text: $name)
            Button(L10n.WalletAddressDrawer.renameAccountAction) {
                guard let slotIndex else { return }
                onSave(slotIndex, name)
            }
            Button(L10n.Common.cancel, role: .cancel, action: onCancel)
        }
    }
}
