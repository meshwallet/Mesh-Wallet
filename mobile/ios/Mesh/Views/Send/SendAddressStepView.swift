import SwiftUI

struct SendAddressStepView: View {
    @ObservedObject var model: SendFlowViewModel
    let onClose: () -> Void
    let onPaste: () -> Void
    let onScanQR: () -> Void
    let onNext: () -> Void

    @FocusState private var addressFocused: Bool
    @FocusState private var amountFocused: Bool
    @State private var isSendSlotExpanded = false
    @State private var showSendToSelfSheet = false

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        if MeshWalletCredentials.supportsHDWalletFeatures() {
                            sendFromSection
                        }
                        recipientSection
                        amountSection
                        sendTypeSection
                        protectionSection

                        if let walletLoadError = model.walletLoadError {
                            Text(walletLoadError)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(Color.orange)
                        }
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.never)

                addressStepFooter
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
        .task(id: model.selectedSendSlotIndex) {
            await model.refreshSenderActivationStatus()
        }
        .meshDismissKeyboardOnSwipeDown()
        .toolbar(.hidden, for: .navigationBar)
        .animation(MeshBalanceRevealAnimation.listExpand, value: isSendSlotExpanded)
        .sheet(isPresented: $showSendToSelfSheet) {
            MeshSendToSelfSheet(
                slots: model.selfTransferDestinationSlots,
                isLoading: model.isLoadingWallet || model.isRefreshingBalance
            ) { slot in
                model.applySelfTransferRecipient(slot)
                showSendToSelfSheet = false
            }
        }
    }

    @ViewBuilder
    private var addressStepFooter: some View {
        MeshPrimaryButton(
            title: L10n.Common.next,
            isEnabled: model.canProceedFromAddressStep
        ) {
            onNext()
        }
        .opacity(model.isAddressStepBusy ? 0.6 : 1)
        .allowsHitTesting(!model.isAddressStepBusy)
        .meshScreenFooterButtons()
    }

    private var header: some View {
        MeshFlowScreenHeader(
            title: L10n.Send.title,
            onClose: onClose,
            trailingText: L10n.Send.stepAddress
        )
    }

    @ViewBuilder
    private var sendRecipientActions: some View {
        if model.canSendToSelf {
            HStack(spacing: 8) {
                MeshSendFieldButton(icon: "doc.on.doc", title: L10n.Common.paste, action: onPaste)
                MeshSendFieldButton(icon: "qrcode.viewfinder", title: L10n.Send.scanQR, action: onScanQR)
                MeshSendFieldButton(
                    icon: "arrow.left.arrow.right",
                    title: L10n.Send.sendToSelf
                ) {
                    showSendToSelfSheet = true
                }
            }
        } else {
            HStack(spacing: 8) {
                MeshSendFieldButton(icon: "doc.on.doc", title: L10n.Common.paste, action: onPaste)
                MeshSendFieldButton(icon: "qrcode.viewfinder", title: L10n.Send.scanQR, action: onScanQR)
            }
        }
    }

    private var sendFromSection: some View {
        MeshWalletSlotPickerView(
            headerTitle: L10n.Send.fromAddress,
            slots: model.sendSlots,
            selectedIndex: model.selectedSendSlotIndex,
            isExpanded: $isSendSlotExpanded,
            isLoading: model.isLoadingWallet || model.isRefreshingBalance,
            showsBalance: true
        ) { index in
            model.selectSendSlot(index)
        }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.Send.recipient)

            TextField(L10n.Send.addressPlaceholder, text: $model.recipientAddress)
                .font(MeshTheme.Typography.body())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .meshTextInputAccent()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($addressFocused)
                .padding(16)
                .meshFieldSurface()
                .onChange(of: model.recipientAddress) { _ in
                    model.addressError = nil
                }

            if let addressError = model.addressError {
                inlineErrorText(addressError)
            }

            sendRecipientActions
                .padding(.top, model.addressError == nil ? 0 : 4)
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.Send.amount)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $model.amountText)
                    .font(MeshTheme.Typography.balanceHero())
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .meshTextInputAccent()
                    .keyboardType(.decimalPad)
                    .textContentType(.none)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($amountFocused)
                    .onChange(of: model.amountText) { newValue in
                        let sanitized = SendAmountParser.sanitizeInput(newValue)
                        if sanitized != newValue {
                            model.amountText = sanitized
                            return
                        }
                        model.amountError = nil
                        model.noteSendInputsChanged()
                    }

                Text("USDT")
                    .font(MeshTheme.Typography.balanceCurrency())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                amountFocused = true
            }

            if let amountError = model.amountError {
                inlineErrorText(amountError)
            }

            HStack(alignment: .center, spacing: 12) {
                Button(action: { model.useMaxAmount() }) {
                    Text(L10n.Send.useMax)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(Capsule().stroke(MeshTheme.Colors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .fixedSize()

                MeshFlowAnimatedAvailableCaption(
                    fullText: model.availableText,
                    isPending: model.isAvailableCaptionPending
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var sendTypeSection: some View {
        // Secure send disabled for now — direct send only.
        EmptyView()
        // if MeshWalletCredentials.supportsHDWalletFeatures() {
        //     sendTypeCard
        // }
    }

    private var sendTypeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Send.type)
                .font(MeshTheme.Typography.sectionTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)

            VStack(spacing: 10) {
                sendTypeRow(
                    title: MeshDefaultSendMethod.direct.title,
                    detail: MeshDefaultSendMethod.direct.detail,
                    fee: MeshSendFees.directSend,
                    timing: MeshDefaultSendMethod.direct.timing,
                    isSelected: !model.isPrivateSendMode
                ) {
                    dismissKeyboardFocus()
                    model.setPrivateSendEnabled(false)
                }

                sendTypeRow(
                    title: MeshPrivateSendMode.standard.title,
                    detail: MeshPrivateSendMode.standard.subtitle,
                    fee: MeshSendFees.standardPrivate,
                    timing: MeshPrivateSendMode.standard.estimatedMinutes,
                    isSelected: model.isPrivateSendMode
                ) {
                    dismissKeyboardFocus()
                    model.setPrivateSendEnabled(true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MeshTheme.Colors.listCardFill,
            in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
        )
    }

    private func sendTypeRow(
        title: String,
        detail: String,
        fee: Decimal,
        timing: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(MeshTheme.Typography.sans(size: 15, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MeshTheme.Colors.accent)
                    }
                }

                Text(detail)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 16) {
                    if MeshSendFees.showsFeeInUI {
                        Text(L10n.Common.feeFormat(MeshSendFees.formattedFee(fee)))
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                    }

                    Text(timing)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MeshTheme.Colors.surfaceElevated.opacity(0.35),
                in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
                    .stroke(isSelected ? MeshTheme.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.Send.protection)

            VStack(alignment: .leading, spacing: 14) {
                protectionRow(L10n.Send.noTrxNeeded, detail: "✓")
                protectionRow(L10n.Send.networkResources, detail: "✓")
                if MeshSendFees.showsFeeInUI {
                    protectionRow(L10n.Send.feeLabel, detail: model.networkFeeText)
                        .animation(.easeInOut(duration: 0.2), value: model.networkFeeText)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                MeshTheme.Colors.listCardFill,
                in: RoundedRectangle(cornerRadius: MeshTheme.Metrics.walletCardRadius, style: .continuous)
            )
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(MeshTheme.Typography.caption())
            .foregroundStyle(MeshTheme.Colors.textSecondary)
    }

    private func inlineErrorText(_ message: String) -> some View {
        Text(message)
            .font(MeshTheme.Typography.caption())
            .foregroundStyle(Color.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeInOut(duration: 0.2), value: message)
    }

    private func dismissKeyboardFocus() {
        addressFocused = false
        amountFocused = false
    }

    private func protectionRow(_ label: String, detail: String) -> some View {
        HStack {
            Text(label)
                .font(MeshTheme.Typography.body())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
            Spacer()
            Text(detail)
                .font(MeshTheme.Typography.body())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
        }
    }
}
