package com.mesh.wallet.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.mesh.wallet.R
import androidx.compose.runtime.rememberCoroutineScope
import com.mesh.wallet.core.MeshClipboard
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.core.session.WalletSession
import com.mesh.wallet.data.MeshWalletRestore
import com.mesh.wallet.data.PhraseValidation
import com.mesh.wallet.data.secure.SecureStorage
import com.mesh.wallet.ui.components.MeshBackButton
import com.mesh.wallet.ui.components.MeshInputPanel
import com.mesh.wallet.ui.components.MeshMultilineField
import com.mesh.wallet.ui.components.MeshOnboardingScreen
import com.mesh.wallet.ui.components.MeshRestoreFieldActions
import com.mesh.wallet.ui.components.MeshTitleBlock
import com.mesh.wallet.ui.components.MeshWalletNameField
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.mesh.wallet.ui.components.MeshPasscodeDots
import com.mesh.wallet.ui.components.MeshPasscodeEntryLayout
import com.mesh.wallet.ui.components.MeshPasscodeKeypad
import com.mesh.wallet.ui.components.MeshPrimaryButton
import com.mesh.wallet.ui.components.MeshSecondaryButton
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography

@Composable
fun AddExistingScreen(
    onBack: () -> Unit,
    onPhrase: () -> Unit,
    onPrivateKey: () -> Unit
) {
    OnboardingScaffold(title = stringResource(R.string.onboarding_add_existing), onBack = onBack) {
        MeshPrimaryButton(title = stringResource(R.string.onboarding_phrase), onClick = onPhrase)
        Spacer(modifier = Modifier.height(12.dp))
        MeshSecondaryButton(title = stringResource(R.string.onboarding_private_key), onClick = onPrivateKey)
    }
}

@Composable
fun RestorePhraseScreen(
    viewModel: OnboardingViewModel,
    session: WalletSession,
    onBack: () -> Unit,
    onContinue: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var walletName by remember { mutableStateOf("") }
    var phraseText by remember { mutableStateOf("") }
    var isPasting by remember { mutableStateOf(false) }
    var validation by remember { mutableStateOf<PhraseValidation>(PhraseValidation.Empty) }
    val error by viewModel.error.collectAsState()
    val isImporting by viewModel.isImporting.collectAsState()
    val namePlaceholder = remember(session.registry.wallets.size) { session.registry.suggestedName() }

    LaunchedEffect(phraseText) {
        if (isPasting) return@LaunchedEffect
        delay(250)
        validation = withContext(Dispatchers.Default) {
            MeshWalletRestore.validatePhrase(phraseText)
        }
    }

    val validationMessage = when (val result = validation) {
        PhraseValidation.Empty -> null
        PhraseValidation.Valid -> "Phrase validated."
        is PhraseValidation.InvalidWordCount -> "Expected 12, 15, 18, 21, or 24 words. Current: ${result.actual}."
        is PhraseValidation.InvalidWord -> "Word ${result.position} is not in the BIP-39 word list."
        PhraseValidation.InvalidChecksum -> "Invalid checksum. Verify order and spelling."
    }
    val validationColor = if (validation == PhraseValidation.Valid) MeshColors.Success else MeshColors.Warning

    MeshOnboardingScreen(
        footer = {
            MeshPrimaryButton(
                title = if (isImporting) L10n.tr(context, "common_generating") else stringResource(R.string.onboarding_restore_phrase_action),
                onClick = { viewModel.restoreFromPhrase(phraseText, walletName, onContinue) },
                enabled = validation == PhraseValidation.Valid && !isImporting && !isPasting
            )
        }
    ) {
        MeshBackButton(onClick = onBack, modifier = Modifier.padding(top = 4.dp))
        Spacer(modifier = Modifier.height(24.dp))
        MeshTitleBlock(
            title = stringResource(R.string.onboarding_restore_phrase_title),
            subtitle = stringResource(R.string.onboarding_restore_phrase_subtitle)
        )
        Spacer(modifier = Modifier.height(24.dp))
        MeshWalletNameField(
            name = walletName,
            onNameChange = { walletName = it },
            placeholder = namePlaceholder
        )
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = stringResource(R.string.onboarding_restore_phrase_title),
            style = MeshTypography.Label,
            color = MeshColors.TextSecondary
        )
        Spacer(modifier = Modifier.height(10.dp))
        MeshInputPanel {
            MeshMultilineField(
                value = phraseText,
                onValueChange = { phraseText = it },
                placeholder = stringResource(R.string.onboarding_restore_phrase_placeholder),
                minHeight = 140.dp
            )
        }
        Spacer(modifier = Modifier.height(12.dp))
        MeshRestoreFieldActions(
            pasteLabel = L10n.Common.paste(context),
            onPaste = {
                if (isPasting || isImporting) return@MeshRestoreFieldActions
                isPasting = true
                scope.launch {
                    val raw = MeshClipboard.pasteString(context)
                    if (raw != null) {
                        val sanitized = withContext(Dispatchers.Default) {
                            MeshWalletRestore.sanitizedPhrasePaste(raw)
                        }
                        phraseText = sanitized
                        validation = MeshWalletRestore.validatePhrase(sanitized)
                    }
                    isPasting = false
                }
            },
            onClear = {
                phraseText = ""
                validation = PhraseValidation.Empty
            },
            isPasting = isPasting,
            enabled = !isImporting
        )
        validationMessage?.let {
            Spacer(modifier = Modifier.height(12.dp))
            Text(text = it, style = MeshTypography.Caption, color = validationColor)
        }
        error?.let {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = if (it == OnboardingViewModel.WALLET_NAME_TAKEN) {
                    stringResource(R.string.error_wallet_name_taken)
                } else {
                    it
                },
                style = MeshTypography.Caption,
                color = MeshColors.Warning
            )
        }
        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
fun RestorePrivateKeyScreen(
    viewModel: OnboardingViewModel,
    session: WalletSession,
    onBack: () -> Unit,
    onContinue: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var walletName by remember { mutableStateOf("") }
    var keyText by remember { mutableStateOf("") }
    var isPasting by remember { mutableStateOf(false) }
    val error by viewModel.error.collectAsState()
    val isImporting by viewModel.isImporting.collectAsState()
    val namePlaceholder = remember(session.registry.wallets.size) { session.registry.suggestedName() }
    val isValidKey = remember(keyText) { MeshWalletRestore.isValidPrivateKeyFormat(keyText) }
    val validationMessage = if (keyText.isBlank()) {
        null
    } else if (isValidKey) {
        "Private key validated."
    } else {
        "Enter 64 hex characters (32 bytes). Optional 0x prefix."
    }

    MeshOnboardingScreen(
        footer = {
            MeshPrimaryButton(
                title = if (isImporting) L10n.tr(context, "common_generating") else stringResource(R.string.onboarding_restore_key_action),
                onClick = { viewModel.restoreFromPrivateKey(keyText, walletName, onContinue) },
                enabled = isValidKey && !isImporting && !isPasting
            )
        }
    ) {
        MeshBackButton(onClick = onBack, modifier = Modifier.padding(top = 4.dp))
        Spacer(modifier = Modifier.height(24.dp))
        MeshTitleBlock(
            title = stringResource(R.string.onboarding_restore_key_title),
            subtitle = stringResource(R.string.onboarding_restore_key_subtitle)
        )
        Spacer(modifier = Modifier.height(24.dp))
        MeshWalletNameField(
            name = walletName,
            onNameChange = { walletName = it },
            placeholder = namePlaceholder
        )
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = stringResource(R.string.onboarding_restore_key_title),
            style = MeshTypography.Label,
            color = MeshColors.TextSecondary
        )
        Spacer(modifier = Modifier.height(10.dp))
        MeshInputPanel {
            MeshMultilineField(
                value = keyText,
                onValueChange = { keyText = it },
                placeholder = stringResource(R.string.onboarding_restore_key_placeholder),
                minHeight = 100.dp,
                monospaced = true
            )
        }
        Spacer(modifier = Modifier.height(12.dp))
        MeshRestoreFieldActions(
            pasteLabel = L10n.Common.paste(context),
            onPaste = {
                if (isPasting || isImporting) return@MeshRestoreFieldActions
                isPasting = true
                scope.launch {
                    val raw = MeshClipboard.pasteString(context, maxCharacters = 256)
                    if (raw != null) {
                        keyText = withContext(Dispatchers.Default) {
                            MeshWalletRestore.normalizePrivateKeyInput(raw)
                        }
                    }
                    isPasting = false
                }
            },
            onClear = { keyText = "" },
            isPasting = isPasting,
            enabled = !isImporting
        )
        validationMessage?.let {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = it,
                style = MeshTypography.Caption,
                color = if (isValidKey) MeshColors.Success else MeshColors.Warning
            )
        }
        error?.let {
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = if (it == OnboardingViewModel.WALLET_NAME_TAKEN) {
                    stringResource(R.string.error_wallet_name_taken)
                } else {
                    it
                },
                style = MeshTypography.Caption,
                color = MeshColors.Warning
            )
        }
        Spacer(modifier = Modifier.height(24.dp))
    }
}

@Composable
fun CreateLaunchScreen(
    viewModel: OnboardingViewModel,
    onBack: () -> Unit,
    onCreated: () -> Unit
) {
    val isGenerating by viewModel.isGenerating.collectAsState()
    val error by viewModel.error.collectAsState()

    LaunchedEffect(Unit) {
        viewModel.generateWallet(onCreated)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
    ) {
        when {
            error != null -> {
                Column(
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(horizontal = MeshMetrics.ScreenPadding),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(text = error.orEmpty(), color = MeshColors.Warning, textAlign = TextAlign.Center)
                    Spacer(modifier = Modifier.height(16.dp))
                    MeshSecondaryButton(title = "Go back", onClick = onBack)
                    Spacer(modifier = Modifier.height(12.dp))
                    MeshPrimaryButton(title = "Retry", onClick = { viewModel.generateWallet(onCreated) })
                }
            }
            isGenerating || error == null -> {
                CircularProgressIndicator(
                    modifier = Modifier.align(Alignment.Center),
                    color = MeshColors.TextPrimary
                )
            }
        }
    }
}

@Composable
fun PasscodeScreen(
    title: String,
    validate: (String) -> Boolean = { true },
    onComplete: (String) -> Unit
) {
    var entered by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }

    MeshPasscodeEntryLayout(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(horizontal = MeshMetrics.ScreenPadding)
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Text(text = title, style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
        Spacer(modifier = Modifier.height(40.dp))
        MeshPasscodeDots(enteredCount = entered.length)
        if (error) {
            Spacer(modifier = Modifier.height(16.dp))
            Text("Passcodes don't match", color = MeshColors.Warning, style = MeshTypography.Caption)
        }
        Spacer(modifier = Modifier.weight(1f))
        MeshPasscodeKeypad(
            onDigit = { digit ->
                if (entered.length < SecureStorage.PASSCODE_LENGTH) {
                    entered += digit
                    if (entered.length == SecureStorage.PASSCODE_LENGTH) {
                        if (validate(entered)) {
                            onComplete(entered)
                        } else {
                            error = true
                            entered = ""
                        }
                    }
                }
            },
            onDelete = {
                error = false
                if (entered.isNotEmpty()) entered = entered.dropLast(1)
            }
        )
        Spacer(modifier = Modifier.height(32.dp))
    }
}

@Composable
fun BiometricScreen(
    session: WalletSession,
    onEnable: () -> Unit,
    onSkip: () -> Unit
) {
    val context = LocalContext.current
    val activity = context as? FragmentActivity

    OnboardingScaffold(title = stringResource(R.string.onboarding_biometric_title)) {
        Text(
            text = stringResource(R.string.onboarding_biometric_subtitle),
            style = MeshTypography.Secondary,
            color = MeshColors.TextSecondary
        )
        Spacer(modifier = Modifier.weight(1f))
        MeshPrimaryButton(
            title = stringResource(R.string.onboarding_biometric_enable),
            onClick = {
                if (activity == null) {
                    onSkip()
                    return@MeshPrimaryButton
                }
                val manager = BiometricManager.from(context)
                if (manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) !=
                    BiometricManager.BIOMETRIC_SUCCESS
                ) {
                    onSkip()
                    return@MeshPrimaryButton
                }
                val executor = ContextCompat.getMainExecutor(context)
                val prompt = BiometricPrompt(
                    activity,
                    executor,
                    object : BiometricPrompt.AuthenticationCallback() {
                        override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                            onEnable()
                        }
                        override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                            onSkip()
                        }
                    }
                )
                prompt.authenticate(
                    BiometricPrompt.PromptInfo.Builder()
                        .setTitle("Enable biometric unlock")
                        .setNegativeButtonText("Skip")
                        .build()
                )
            }
        )
        Spacer(modifier = Modifier.height(12.dp))
        MeshSecondaryButton(title = stringResource(R.string.onboarding_biometric_skip), onClick = onSkip)
    }
}

@Composable
fun WalletReadyScreen(onContinue: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .statusBarsPadding()
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
        ) {
            com.mesh.wallet.ui.components.MeshBundleVideoPlayer(
                modifier = Modifier.fillMaxSize()
            )
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .height(120.dp)
                    .background(
                        androidx.compose.ui.graphics.Brush.verticalGradient(
                            colors = listOf(
                                Color.Transparent,
                                MeshColors.Background.copy(alpha = 0.35f),
                                MeshColors.Background
                            )
                        )
                    )
            )
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MeshColors.Background)
                .padding(horizontal = MeshMetrics.ScreenPadding)
                .padding(top = 4.dp, bottom = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = stringResource(R.string.onboarding_wallet_ready_title),
                style = MeshTypography.ScreenTitle.copy(fontSize = 34.sp),
                color = MeshColors.TextPrimary,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = stringResource(R.string.onboarding_wallet_ready_subtitle),
                style = MeshTypography.Secondary,
                color = MeshColors.TextSecondary,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(28.dp))
            MeshPrimaryButton(
                title = stringResource(R.string.onboarding_wallet_ready_open),
                onClick = onContinue
            )
        }
    }
}

@Composable
private fun OnboardingScaffold(
    title: String,
    onBack: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MeshColors.Background)
            .padding(MeshMetrics.ScreenPadding)
            .verticalScroll(rememberScrollState())
    ) {
        if (onBack != null) {
            MeshBackButton(onClick = onBack)
            Spacer(modifier = Modifier.height(24.dp))
        } else {
            Spacer(modifier = Modifier.height(48.dp))
        }
        Text(text = title, style = MeshTypography.ScreenTitle, color = MeshColors.TextPrimary)
        Spacer(modifier = Modifier.height(24.dp))
        Column(modifier = Modifier.fillMaxSize(), content = content)
    }
}

@Composable
private fun meshFieldColors() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = MeshColors.Accent,
    unfocusedBorderColor = MeshColors.Border,
    focusedContainerColor = MeshColors.FieldFill,
    unfocusedContainerColor = MeshColors.FieldFill,
    focusedTextColor = MeshColors.TextPrimary,
    unfocusedTextColor = MeshColors.TextPrimary,
    cursorColor = MeshColors.Accent
)

private typealias ColumnScope = androidx.compose.foundation.layout.ColumnScope
