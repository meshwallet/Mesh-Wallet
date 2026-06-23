import Foundation

/// Typed localization accessors — keys live in `Localizable.xcstrings`.
enum L10n {
    enum Language {
        static var title: String { MeshL10n.tr("language.title") }
        static var subtitle: String { MeshL10n.tr("language.subtitle") }
    }

    enum Common {
        static var ok: String { MeshL10n.tr("common.ok") }
        static var cancel: String { MeshL10n.tr("common.cancel") }
        static var close: String { MeshL10n.tr("common.close") }
        static var continue_: String { MeshL10n.tr("common.continue") }
        static var next: String { MeshL10n.tr("common.next") }
        static var done: String { MeshL10n.tr("common.done") }
        static var paste: String { MeshL10n.tr("common.paste") }
        static var copy: String { MeshL10n.tr("common.copy") }
        static var copied: String { MeshL10n.tr("common.copied") }
        static var contact: String { MeshL10n.tr("common.contact") }
        static var defaultLabel: String { MeshL10n.tr("common.default") }
        static var fee: String { MeshL10n.tr("common.fee") }
        static var and: String { MeshL10n.tr("common.and") }
        static var saving: String { MeshL10n.tr("common.saving") }
        static var generating: String { MeshL10n.tr("common.generating") }

        static func feeFormat(_ amount: String) -> String {
            MeshL10n.tr("send.fee.format", amount)
        }
    }

    enum Welcome {
        static var brand: String { MeshL10n.tr("welcome.brand") }
        static var tagline: String { MeshL10n.tr("welcome.tagline") }
        static var create: String { MeshL10n.tr("welcome.create") }
        static var restore: String { MeshL10n.tr("welcome.restore") }
        static var legalPrefix: String { MeshL10n.tr("welcome.legal.prefix") }
        static var terms: String { MeshL10n.tr("welcome.legal.terms") }
        static var privacy: String { MeshL10n.tr("welcome.legal.privacy") }
    }

    enum Onboarding {
        static var createIntroTitle: String { MeshL10n.tr("onboarding.create.intro.title") }
        static var createIntroSubtitle: String { MeshL10n.tr("onboarding.create.intro.subtitle") }
        static var createIntroWarning: String { MeshL10n.tr("onboarding.create.intro.warning") }
        static var generateRecoveryPhrase: String { MeshL10n.tr("onboarding.create.intro.generate") }
        static var recoveryTitle: String { MeshL10n.tr("onboarding.recovery.title") }
        static var recoverySubtitle: String { MeshL10n.tr("onboarding.recovery.subtitle") }
        static var recoveryConfirm: String { MeshL10n.tr("onboarding.recovery.confirm") }
        static var recoveryCopy: String { MeshL10n.tr("onboarding.recovery.copy") }
        static var recoveryCopiedWarning: String { MeshL10n.tr("onboarding.recovery.copied.warning") }
        static var recoveryNeverShare: String { MeshL10n.tr("onboarding.recovery.never.share") }
        static var restorePhraseTitle: String { MeshL10n.tr("onboarding.restore.phrase.title") }
        static var restorePhraseSubtitle: String { MeshL10n.tr("onboarding.restore.phrase.subtitle") }
        static var restorePhrasePlaceholder: String { MeshL10n.tr("onboarding.restore.phrase.placeholder") }
        static var restoreKeyTitle: String { MeshL10n.tr("onboarding.restore.key.title") }
        static var restoreKeySubtitle: String { MeshL10n.tr("onboarding.restore.key.subtitle") }
        static var restoreKeyAction: String { MeshL10n.tr("onboarding.restore.key.action") }
        static var restoreKeyPlaceholder: String { MeshL10n.tr("onboarding.restore.key.placeholder") }
        static var restorePhraseAction: String { MeshL10n.tr("onboarding.restore.phrase.action") }
        static var addExistingSubtitle: String { MeshL10n.tr("onboarding.add.existing.subtitle") }
        static var addExistingTitle: String { MeshL10n.tr("onboarding.add.existing.title") }
        static var walletReadyTitle: String { MeshL10n.tr("onboarding.wallet.ready.title") }
        static var walletReadySubtitle: String { MeshL10n.tr("onboarding.wallet.ready.subtitle") }
        static var walletReadyOpen: String { MeshL10n.tr("onboarding.wallet.ready.open") }
    }

    enum Settings {
        static var title: String { MeshL10n.tr("settings.title") }
        static var passcode: String { MeshL10n.tr("settings.passcode") }
        static var passcodeChange: String { MeshL10n.tr("settings.passcode.change") }
        static var passcodeSetupHint: String { MeshL10n.tr("settings.passcode.setup.hint") }
        static var recoveryPhrase: String { MeshL10n.tr("settings.recovery.phrase") }
        static var recoveryRequiresPasscode: String { MeshL10n.tr("settings.recovery.requires.passcode") }
        static var viewRecoveryPhrase: String { MeshL10n.tr("settings.view.recovery.phrase") }
        static var viewRecoverySubtitle: String { MeshL10n.tr("settings.view.recovery.subtitle") }
        static var viewRecoveryBiometricReason: String { MeshL10n.tr("settings.view.recovery.biometric.reason") }

        static func viewRecoverySubtitleBiometric(_ name: String) -> String {
            MeshL10n.tr("settings.view.recovery.subtitle.biometric", name)
        }
        static var contactSupport: String { MeshL10n.tr("settings.contact.support") }
        static var removeWallet: String { MeshL10n.tr("settings.remove.wallet") }
        static var removeConfirmTitle: String { MeshL10n.tr("settings.remove.confirm.title") }
        static var removeConfirmPhrase: String { MeshL10n.tr("settings.remove.confirm.phrase") }
        static var removeConfirmKey: String { MeshL10n.tr("settings.remove.confirm.key") }
        static var removeAction: String { MeshL10n.tr("settings.remove.action") }
        static var passcodeUpdatedTitle: String { MeshL10n.tr("settings.passcode.updated.title") }
        static var passcodeUpdatedMessage: String { MeshL10n.tr("settings.passcode.updated.message") }
        static var recoveryUnavailable: String { MeshL10n.tr("settings.recovery.unavailable") }
        static var recoveryNoWallet: String { MeshL10n.tr("settings.recovery.no.wallet") }
        static var recoveryNotStored: String { MeshL10n.tr("settings.recovery.not.stored") }
        static var biometricSetupFirst: String { MeshL10n.tr("settings.biometric.setup.first") }
        static var biometricUnavailableDevice: String { MeshL10n.tr("settings.biometric.unavailable.device") }
        static var biometricNotAvailable: String { MeshL10n.tr("settings.biometric.not.available") }

        static func biometricSetupSettings(_ name: String) -> String {
            MeshL10n.tr("settings.biometric.setup.settings", name)
        }
        static func biometricUnlockHint(_ name: String) -> String {
            MeshL10n.tr("settings.biometric.unlock.hint", name)
        }
        static func biometricConfirm(_ name: String) -> String {
            MeshL10n.tr("settings.biometric.confirm", name)
        }
        static func biometricNotSetup(_ name: String) -> String {
            MeshL10n.tr("settings.biometric.not.setup", name)
        }
        static func biometricEnableReason(_ name: String) -> String {
            MeshL10n.tr("settings.biometric.enable.reason", name)
        }
    }

    enum Wallet {
        static var fund: String { MeshL10n.tr("wallet.fund") }
        static var send: String { MeshL10n.tr("wallet.send") }
        static var receive: String { MeshL10n.tr("wallet.receive") }
        static var activity: String { MeshL10n.tr("wallet.activity") }
        static var activityEmpty: String { MeshL10n.tr("wallet.activity.empty") }
        static var filterAll: String { MeshL10n.tr("wallet.activity.filter.all") }
        static var filterReceived: String { MeshL10n.tr("wallet.activity.filter.received") }
        static var filterSent: String { MeshL10n.tr("wallet.activity.filter.sent") }
        static var balanceHidden: String { MeshL10n.tr("wallet.balance.hidden") }
        static var homeTotalAmountLabel: String { MeshL10n.tr("wallet.home.total.amount.label") }
        static var balanceBreakdown: String { MeshL10n.tr("wallet.balance.breakdown") }
        static var otherAddresses: String { MeshL10n.tr("wallet.other.addresses") }
        static var today: String { MeshL10n.tr("wallet.today") }
    }

    enum Privacy {
        static var title: String { MeshL10n.tr("privacy.title") }
        static var receiveTitle: String { MeshL10n.tr("privacy.receive.title") }
        static var receiveBody: String { MeshL10n.tr("privacy.receive.body") }
        static var sendTitle: String { MeshL10n.tr("privacy.send.title") }
        static var sendBody: String { MeshL10n.tr("privacy.send.body") }
        static var protectionTitle: String { MeshL10n.tr("privacy.protection.title") }
        static var protectionItem1: String { MeshL10n.tr("privacy.protection.item1") }
        static var protectionItem2: String { MeshL10n.tr("privacy.protection.item2") }
        static var protectionItem3: String { MeshL10n.tr("privacy.protection.item3") }
        static var consolidateTitle: String { MeshL10n.tr("privacy.consolidate.title") }
        static var consolidateHint: String { MeshL10n.tr("privacy.consolidate.hint") }
        static var consolidateButton: String { MeshL10n.tr("privacy.consolidate.button") }
        static var consolidateRunning: String { MeshL10n.tr("privacy.consolidate.running") }

        static func consolidateDone(_ transferCount: Int) -> String {
            MeshL10n.tr("privacy.consolidate.done", String(transferCount))
        }

        static func consolidateProgress(current: Int, total: Int) -> String {
            MeshL10n.tr(
                "privacy.consolidate.progress",
                String(current),
                String(total)
            )
        }
    }

    enum Send {
        static var title: String { MeshL10n.tr("send.title") }
        static var recipient: String { MeshL10n.tr("send.step.recipient") }
        static var amount: String { MeshL10n.tr("send.step.amount") }
        static var type: String { MeshL10n.tr("send.step.type") }
        static var protection: String { MeshL10n.tr("send.step.protection") }
        static var review: String { MeshL10n.tr("send.step.review") }
        static var stepProgress: String { MeshL10n.tr("send.step.progress") }
        static var stepAddress: String { MeshL10n.tr("send.step.address") }
        static var stepAmount: String { MeshL10n.tr("send.step.amount.step") }
        static var addressPlaceholder: String { MeshL10n.tr("send.address.placeholder") }
        static var scanQR: String { MeshL10n.tr("send.scan.qr") }
        static var sendToSelf: String { MeshL10n.tr("send.send.to.self") }
        static var useMax: String { MeshL10n.tr("send.use.max") }
        static var feeLabel: String { MeshL10n.tr("send.fee.label") }
        static var noTrxNeeded: String { MeshL10n.tr("send.no.trx.needed") }
        static var networkResources: String { MeshL10n.tr("send.network.resources") }
        static var reviewWarning: String { MeshL10n.tr("send.warning.review") }
        static var slideConfirm: String { MeshL10n.tr("send.slide.confirm") }
        static var preparingNetwork: String { MeshL10n.tr("send.preparing.network") }
        static var reviewPrepCheckingAddress: String { MeshL10n.tr("send.review.prep.checkingAddress") }
        static var reviewPrepActivatingOnTron: String { MeshL10n.tr("send.review.prep.activatingOnTron") }
        static var reviewPrepWaitingActivation: String { MeshL10n.tr("send.review.prep.waitingActivation") }
        static var reviewPrepRetryingActivation: String { MeshL10n.tr("send.review.prep.retryingActivation") }
        static var reviewPrepCheckingNetwork: String { MeshL10n.tr("send.review.prep.checkingNetwork") }
        static var reviewPrepRequestingEnergy: String { MeshL10n.tr("send.review.prep.requestingEnergy") }
        static var reviewPrepWaitingEnergy: String { MeshL10n.tr("send.review.prep.waitingEnergy") }
        static var reviewPrepWaitingResources: String { MeshL10n.tr("send.review.prep.waitingResources") }
        static var reviewPrepPreparingBandwidth: String { MeshL10n.tr("send.review.prep.preparingBandwidth") }
        static var reviewPrepWaitingBandwidth: String { MeshL10n.tr("send.review.prep.waitingBandwidth") }
        static var reviewPrepRetryingNetwork: String { MeshL10n.tr("send.review.prep.retryingNetwork") }
        static var reviewPrepPreparingFee: String { MeshL10n.tr("send.review.prep.preparingFee") }
        static var reviewPrepHintActivation: String { MeshL10n.tr("send.review.prep.hint.activation") }
        static var reviewPrepHintNetwork: String { MeshL10n.tr("send.review.prep.hint.network") }
        static var reviewPrepHintFee: String { MeshL10n.tr("send.review.prep.hint.fee") }
        static var reviewPrepHintGeneric: String { MeshL10n.tr("send.review.prep.hint.generic") }
        static var processing: String { MeshL10n.tr("send.processing") }
        static var sent: String { MeshL10n.tr("send.sent") }
        static var failed: String { MeshL10n.tr("send.failed") }
        static var processingSubtitle: String { MeshL10n.tr("send.processing.subtitle") }
        static var processingHintDirect: String { MeshL10n.tr("send.processing.hint.direct") }
        static var processingHintPrivate: String { MeshL10n.tr("send.processing.hint.private") }
        static var processingPreparing: String { MeshL10n.tr("send.processing.preparing") }
        static var processingPreparingHint: String { MeshL10n.tr("send.processing.preparing.hint") }
        static var processingActivating: String { MeshL10n.tr("send.processing.activating") }
        static var processingActivatingSubtitle: String { MeshL10n.tr("send.processing.activating.subtitle") }
        static var processingActivatingHint: String { MeshL10n.tr("send.processing.activating.hint") }
        static var processingActivatingKeepOpen: String { MeshL10n.tr("send.processing.activating.keepOpen") }
        static var processingBackgroundSafe: String { MeshL10n.tr("send.processing.background.safe") }
        static var transactionDetails: String { MeshL10n.tr("send.transaction.details") }
        static var methodDirect: String { MeshL10n.tr("send.method.direct") }
        static var methodPrivate: String { MeshL10n.tr("send.method.private") }
        static var methodDirectDetail: String { MeshL10n.tr("send.method.direct.detail") }
        static var methodPrivateDetail: String { MeshL10n.tr("send.method.private.detail") }
        static var methodPrivateHops: String { MeshL10n.tr("send.method.private.hops") }
        static var timingDirect: String { MeshL10n.tr("send.timing.direct") }
        static var timingPrivate: String { MeshL10n.tr("send.timing.private") }

        static func available(_ amount: String) -> String {
            MeshL10n.tr("send.available", amount)
        }
        static func availableMulti(_ amount: String) -> String {
            MeshL10n.tr("send.available.multi", amount)
        }

        static func availableOnSlot(_ amount: String) -> String {
            MeshL10n.tr("send.available.on.slot", amount)
        }

        static var fromAddress: String { MeshL10n.tr("send.from.address") }
        static var activateAddress: String { MeshL10n.tr("send.activate.address") }
        static var activatingAddress: String { MeshL10n.tr("send.activating.address") }
        static var activationTimeout: String { MeshL10n.tr("send.activation.timeout") }
        static func privateRouteHint(step: Int, total: Int) -> String {
            String(format: MeshL10n.tr("send.private.route.hint"), step, total)
        }

        static var reviewTitle: String { MeshL10n.tr("send.review.title") }
        static var reviewSending: String { MeshL10n.tr("send.review.sending") }
        static var reviewTo: String { MeshL10n.tr("send.review.to") }
        static var reviewNetwork: String { MeshL10n.tr("send.review.network") }
        static var reviewTotal: String { MeshL10n.tr("send.review.total") }
        static var reviewArrives: String { MeshL10n.tr("send.review.arrives") }
        static var reviewPrivateDeposit: String { MeshL10n.tr("send.review.private.deposit") }
        static var preparing: String { MeshL10n.tr("send.preparing") }
        static var keepOpen: String { MeshL10n.tr("send.keep.open") }
        static var failedFeeHint: String { MeshL10n.tr("send.outcome.failed.fee.hint") }
        static var activityHint: String { MeshL10n.tr("send.outcome.activity.hint") }
        static var deepRecoveryTitle: String { MeshL10n.tr("send.deep.recovery.title") }
        static var deepRecoveryHint: String { MeshL10n.tr("send.deep.recovery.hint") }
        static var deepRecoveryButton: String { MeshL10n.tr("send.deep.recovery.button") }
        static var deepRecoveryScanning: String { MeshL10n.tr("send.deep.recovery.scanning") }
        static var deepRecoveryTransferring: String { MeshL10n.tr("send.deep.recovery.transferring") }

        static func deepRecoveryScanProgress(checked: Int, total: Int) -> String {
            MeshL10n.tr(
                "send.deep.recovery.scanProgress",
                String(checked),
                String(total)
            )
        }

        static func deepRecoveryTransferProgress(current: Int, total: Int) -> String {
            MeshL10n.tr(
                "send.deep.recovery.transferProgress",
                String(current),
                String(total)
            )
        }

        static func deepRecoveryDone(_ transferCount: Int) -> String {
            MeshL10n.tr("send.deep.recovery.done", String(transferCount))
        }

        static var deepRecoveryRateLimited: String {
            MeshL10n.tr("send.deep.recovery.rateLimited")
        }

        static func deepRecoveryHomeBanner(checked: Int, total: Int) -> String {
            MeshL10n.tr(
                "send.deep.recovery.homeBanner",
                String(checked),
                String(total)
            )
        }
    }

    enum Ticker {
        static var networkFees: String { MeshL10n.tr("ticker.network.fees") }
    }

    enum WalletAddressDrawer {
        static var title: String { MeshL10n.tr("wallet.address.drawer.title") }
        static var subtitle: String { MeshL10n.tr("wallet.address.drawer.subtitle") }
        static var createAccountHint: String { MeshL10n.tr("wallet.address.drawer.create.hint") }
        static var mainBadge: String { MeshL10n.tr("wallet.address.drawer.main.badge") }
        static var totalLabel: String { MeshL10n.tr("wallet.address.drawer.total.label") }

        static func balanceSlot(_ number: Int) -> String {
            MeshL10n.tr("receive.balance.slot", String(number))
        }

        static var generateBalance: String { MeshL10n.tr("receive.generate.balance") }
        static var createBalanceTitle: String { MeshL10n.tr("wallet.address.drawer.create.title") }
        static var createBalancePlaceholder: String { MeshL10n.tr("wallet.address.drawer.create.placeholder") }
        static var createBalanceAction: String { MeshL10n.tr("wallet.address.drawer.create.action") }
        static var renameAccountTitle: String { MeshL10n.tr("wallet.address.drawer.rename.title") }
        static var renameAccountAction: String { MeshL10n.tr("wallet.address.drawer.rename.action") }
        static var renameAccountAccessibility: String { MeshL10n.tr("wallet.address.drawer.rename.accessibility") }
        static var activationActive: String { MeshL10n.tr("wallet.address.drawer.activation.active") }
        static var activationInactive: String { MeshL10n.tr("wallet.address.drawer.activation.inactive") }
    }

    enum WalletSelect {
        static var title: String { MeshL10n.tr("wallet.select.title") }
        static var addExisting: String { MeshL10n.tr("wallet.select.add.existing") }
        static var createNew: String { MeshL10n.tr("wallet.select.create.new") }
        static var menuRename: String { MeshL10n.tr("wallet.select.menu.rename") }
        static var menuBackup: String { MeshL10n.tr("wallet.select.menu.backup") }
        static var menuRemove: String { MeshL10n.tr("wallet.select.menu.remove") }
    }

    enum Receive {
        static var title: String { MeshL10n.tr("receive.title") }
        static var mainAddress: String { MeshL10n.tr("receive.address.main") }
        static var mainBadge: String { MeshL10n.tr("receive.main.badge") }
        static var generateAddress: String { MeshL10n.tr("receive.generate.address") }
        static var chooseAddressHint: String { MeshL10n.tr("receive.choose.address.hint") }
        static var receiveOnAddress: String { MeshL10n.tr("receive.on.address") }
        static var shareFooter: String { MeshL10n.tr("receive.share.footer") }

        static func addressSlot(_ number: Int) -> String {
            MeshL10n.tr("receive.address.slot", String(number))
        }

        static func balanceSlot(_ number: Int) -> String {
            MeshL10n.tr("receive.balance.slot", String(number))
        }

        static func depthIndex(_ index: Int) -> String {
            MeshL10n.tr("receive.depth.index", String(index))
        }

        static var showMore: String { MeshL10n.tr("receive.show.more") }
        static var deleteAddressTitle: String { MeshL10n.tr("receive.delete.address.title") }
        static var deleteAddressAction: String { MeshL10n.tr("receive.delete.address.action") }

        static func deleteAddressMessage(_ title: String) -> String {
            MeshL10n.tr("receive.delete.address.message", title)
        }

        static func deleteAddressDetailBalance(_ title: String) -> String {
            MeshL10n.tr("receive.delete.address.detail.balance", title)
        }

        static func deleteAddressDetailAccountIndex(_ index: Int) -> String {
            MeshL10n.tr("receive.delete.address.detail.account_index", String(index))
        }

        static func deleteAddressDetailPath(_ path: String) -> String {
            MeshL10n.tr("receive.delete.address.detail.path", path)
        }

        static func deleteAddressDetailAddress(_ address: String) -> String {
            MeshL10n.tr("receive.delete.address.detail.address", address)
        }

        static var deleteAddressDetailFooter: String {
            MeshL10n.tr("receive.delete.address.detail.footer")
        }
    }

    enum Security {
        static var lockTitle: String { MeshL10n.tr("security.lock.title") }
        static var lockSubtitle: String { MeshL10n.tr("security.lock.subtitle") }
        static var passcodeIncorrect: String { MeshL10n.tr("security.passcode.incorrect") }
        static var changePasscode: String { MeshL10n.tr("security.change.passcode") }
        static var createPasscode: String { MeshL10n.tr("security.create.passcode") }
        static var confirmPasscode: String { MeshL10n.tr("security.confirm.passcode") }

        static func unlockWith(_ name: String) -> String {
            MeshL10n.tr("security.lock.faceid", name)
        }
    }

    enum Error {
        static var invalidRecoveryPhrase: String { MeshL10n.tr("error.invalid.recovery.phrase") }
        static var walletMismatch: String { MeshL10n.tr("error.wallet.mismatch") }
        static var balanceLoad: String { MeshL10n.tr("error.balance.load") }

        static var amountExceeds: String { MeshL10n.tr("error.amount.exceeds") }
        static func amountBelowFee(_ fee: String) -> String {
            MeshL10n.tr("error.amount.below.fee", fee)
        }
        static var walletNameTaken: String { MeshL10n.tr("error.wallet.name.taken") }
    }

    enum AIOrganizer {
        static var title: String { MeshL10n.tr("ai.organizer.title") }
        static var subtitle: String { MeshL10n.tr("ai.organizer.subtitle") }
    }

    enum AppUpdate {
        static var title: String { MeshL10n.tr("appUpdate.title") }
        static var update: String { MeshL10n.tr("appUpdate.update") }

        static func message(_ version: String) -> String {
            MeshL10n.tr("appUpdate.message", version)
        }
    }

    enum Exposure {
        static var privateBalance: String { MeshL10n.tr("exposure.private.balance") }
        static var walletExposure: String { MeshL10n.tr("exposure.wallet.exposure") }
        static var reduceHint: String { MeshL10n.tr("exposure.reduce.hint") }
    }

    enum Transaction {
        static var sent: String { MeshL10n.tr("transaction.sent") }
        static var received: String { MeshL10n.tr("transaction.received") }
        static var processing: String { MeshL10n.tr("transaction.processing") }
    }

    enum TransferProof {
        static var transferSent: String { MeshL10n.tr("transfer.proof.transfer.sent") }
        static var transferReceived: String { MeshL10n.tr("transfer.proof.transfer.received") }
        static var confirmed: String { MeshL10n.tr("transfer.proof.confirmed") }
        static var confirmedOnNetwork: String { MeshL10n.tr("transfer.proof.confirmed.on.network") }
        static var processingOnNetwork: String { MeshL10n.tr("transfer.proof.processing.on.network") }
        static var status: String { MeshL10n.tr("transfer.proof.status") }
        static var networkLabel: String { MeshL10n.tr("transfer.proof.network.label") }
        static var network: String { MeshL10n.tr("transfer.proof.network") }
        static var to: String { MeshL10n.tr("transfer.proof.to") }
        static var from: String { MeshL10n.tr("transfer.proof.from") }
        static var tx: String { MeshL10n.tr("transfer.proof.tx") }
        static var date: String { MeshL10n.tr("transfer.proof.date") }
        static var sentWithMesh: String { MeshL10n.tr("transfer.proof.sent.with.mesh") }
        static var receivedWithMesh: String { MeshL10n.tr("transfer.proof.received.with.mesh") }
        static var tagline: String { MeshL10n.tr("transfer.proof.tagline") }
        static var shareProof: String { MeshL10n.tr("transfer.proof.share") }
        static var copyDetails: String { MeshL10n.tr("transfer.proof.copy.details") }
        static var cleanScreenshot: String { MeshL10n.tr("transfer.proof.clean.screenshot") }
        static var readyScreenshot: String { MeshL10n.tr("transfer.proof.ready.screenshot") }
        static var screenshotHint: String { MeshL10n.tr("transfer.proof.screenshot.hint") }
        static var shareTextReceipt: String { MeshL10n.tr("transfer.proof.share.text") }
        static var shareImageReceipt: String { MeshL10n.tr("transfer.proof.share.image") }
        static var copyTx: String { MeshL10n.tr("transfer.proof.copy.tx") }
        static var copyTxHash: String { copyTx }
        static var detailsTitle: String { MeshL10n.tr("transfer.proof.details.title") }
        static var detailsField: String { MeshL10n.tr("transfer.proof.details.field") }
        static var viewOnTronscan: String { MeshL10n.tr("transfer.proof.view.tronscan") }

        static func amountSent(_ amount: String) -> String {
            MeshL10n.tr("transfer.proof.amount.sent", amount)
        }

        static func amountReceived(_ amount: String) -> String {
            MeshL10n.tr("transfer.proof.amount.received", amount)
        }
    }
}
