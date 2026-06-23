package com.mesh.wallet.ui.home

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mesh.wallet.R
import com.mesh.wallet.core.l10n.L10n
import com.mesh.wallet.domain.model.WalletTransaction
import com.mesh.wallet.ui.components.MeshWalletCircleActionButton
import com.mesh.wallet.ui.components.meshBalancePrivacyBlur
import com.mesh.wallet.ui.theme.MeshColors
import com.mesh.wallet.ui.theme.MeshMetrics
import com.mesh.wallet.ui.theme.MeshTypography
import com.mesh.wallet.ui.theme.MeshWalletHomeColors
import com.mesh.wallet.ui.wallet.SelectWalletSheet
import com.mesh.wallet.ui.wallet.WalletAddressDrawer

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletHomeScreen(
    viewModel: WalletHomeViewModel,
    onSend: () -> Unit,
    onReceive: () -> Unit,
    onSecurity: () -> Unit,
    onPrivacy: () -> Unit,
    onTransactionClick: (WalletTransaction) -> Unit,
    onCreateWallet: () -> Unit = {},
    onAddExistingWallet: () -> Unit = {},
    onWalletRemoved: () -> Unit = {},
    session: com.mesh.wallet.core.session.WalletSession? = null
) {
    val context = LocalContext.current
    val walletName by viewModel.walletName.collectAsState()
    val focusedBalance by viewModel.focusedSlotBalance.collectAsState()
    val formattedBalance by remember(focusedBalance) { derivedStateOf { viewModel.formattedBalance } }
    val transactions by viewModel.filteredTransactions.collectAsState()
    val isInitialLoading by viewModel.isInitialLoading.collectAsState()
    val isPullRefreshing by viewModel.isPullRefreshing.collectAsState()
    val filter by viewModel.activityFilter.collectAsState()
    val slots by viewModel.receiveSlots.collectAsState()
    val showsMulti by viewModel.showsMultiAccountChrome.collectAsState()
    val wallets by viewModel.wallets.collectAsState()
    val focusedSlotIndex by viewModel.focusedSlotIndex.collectAsState()
    val activeWalletId = viewModel.activeWalletId
    val showsAccountCaption = viewModel.showsHomeAccountCaption
    val accountCaption = viewModel.focusedAccountTitle(L10n.WalletAddressDrawer.mainBadge(context))

    var showWalletPicker by remember { mutableStateOf(false) }
    var showAddressDrawer by remember { mutableStateOf(false) }
    var balanceHidden by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()
    val collapseProgress by remember {
        derivedStateOf {
            val offset = listState.firstVisibleItemScrollOffset.toFloat()
            val index = listState.firstVisibleItemIndex
            val total = offset + index * 400f
            (total / 280f).coerceIn(0f, 1f)
        }
    }
    val heroAlpha by animateFloatAsState(1f - collapseProgress * 0.5f)
    val actionsAlpha by animateFloatAsState((1f - collapseProgress * 2.5f).coerceIn(0f, 1f))
    val filterAlpha by animateFloatAsState(collapseProgress.coerceIn(0f, 1f))
    val balanceScale by animateFloatAsState(1f - collapseProgress * 0.2f)
    val groupedTransactions = remember(transactions) { transactions.groupedByDay(context) }

    LaunchedEffect(Unit) { viewModel.refreshWallet() }

    Box(modifier = Modifier.fillMaxSize().background(MeshWalletHomeColors.bottomSurface)) {
        PullToRefreshBox(
            isRefreshing = isPullRefreshing,
            onRefresh = { viewModel.pullToRefresh() },
            modifier = Modifier.fillMaxSize()
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier.fillMaxSize()
            ) {
                item {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(360.dp)
                            .background(MeshWalletHomeColors.heroScrollFade)
                    ) {
                        Column(
                            modifier = Modifier
                                .fillMaxSize()
                                .statusBarsPadding()
                                .padding(horizontal = MeshMetrics.ScreenPadding)
                                .alpha(heroAlpha)
                        ) {
                            Spacer(modifier = Modifier.height(16.dp))
                            HomeHeader(
                                walletName = walletName,
                                showsMulti = showsMulti,
                                walletTotal = viewModel.formattedWalletTotal,
                                balanceHidden = balanceHidden,
                                onDrawer = { showAddressDrawer = true },
                                onWalletPicker = { showWalletPicker = true },
                                onSecurity = onSecurity
                            )

                            Box(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxWidth(),
                                contentAlignment = Alignment.Center
                            ) {
                                HomeBalanceSection(
                                    formattedBalance = formattedBalance,
                                    balanceHidden = balanceHidden,
                                    isPullRefreshing = isPullRefreshing,
                                    balanceScale = balanceScale,
                                    collapseProgress = collapseProgress,
                                    accountCaption = accountCaption,
                                    showsAccountCaption = showsAccountCaption,
                                    onToggleVisibility = { balanceHidden = !balanceHidden }
                                )
                            }

                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(bottom = 20.dp)
                                    .alpha(actionsAlpha),
                                horizontalArrangement = Arrangement.spacedBy(88.dp, Alignment.CenterHorizontally)
                            ) {
                                MeshWalletCircleActionButton(
                                    title = L10n.Wallet.receive(context),
                                    onClick = onReceive
                                )
                                MeshWalletCircleActionButton(
                                    title = L10n.Wallet.send(context),
                                    onClick = onSend
                                )
                            }
                        }

                        ActivityFilterBar(
                            selected = filter,
                            onSelect = viewModel::setActivityFilter,
                            modifier = Modifier
                                .align(Alignment.BottomCenter)
                                .fillMaxWidth()
                                .alpha(filterAlpha)
                                .padding(horizontal = MeshMetrics.ScreenPadding, vertical = 12.dp)
                        )
                    }
                }

                if (transactions.isEmpty() && !isInitialLoading) {
                    item {
                        Column(
                            modifier = Modifier.fillMaxWidth().padding(32.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Image(
                                painter = painterResource(R.drawable.wallet_empty_chart),
                                contentDescription = null,
                                modifier = Modifier.size(44.dp).alpha(0.55f)
                            )
                            Spacer(modifier = Modifier.height(14.dp))
                            Text(
                                L10n.Wallet.activityEmpty(context),
                                style = MeshTypography.Body.copy(fontSize = 16.sp),
                                color = MeshColors.TextTertiary
                            )
                        }
                    }
                } else {
                    groupedTransactions.forEach { group ->
                        item(key = "header-${group.day}") {
                            WalletActivitySectionHeader(
                                title = group.day,
                                modifier = Modifier.padding(horizontal = MeshMetrics.ScreenPadding)
                            )
                        }
                        items(group.items, key = { it.id }) { tx ->
                            WalletHomeTransactionRow(
                                tx = tx,
                                balanceHidden = balanceHidden,
                                modifier = Modifier.padding(horizontal = MeshMetrics.ScreenPadding),
                                onClick = { onTransactionClick(tx) }
                            )
                        }
                    }
                }
                item { Spacer(modifier = Modifier.height(80.dp)) }
            }
        }

        WalletAddressDrawer(
            visible = showAddressDrawer,
            slots = slots,
            focusedIndex = focusedSlotIndex,
            canAdd = viewModel.canAddReceiveAddress,
            walletTotal = if (showsMulti) viewModel.formattedWalletTotal else null,
            onDismiss = { showAddressDrawer = false },
            onSelectSlot = { viewModel.setFocusedSlot(it) },
            onAddAddress = { viewModel.addReceiveAddress() }
        )

        session?.let { walletSession ->
            SelectWalletSheet(
                visible = showWalletPicker,
                wallets = wallets,
                activeWalletId = activeWalletId,
                session = walletSession,
                onDismiss = { showWalletPicker = false },
                onSelect = {
                    viewModel.switchWallet(it)
                    showWalletPicker = false
                },
                onWalletRenamed = { viewModel.refreshWallet() },
                onWalletRemoved = {
                    viewModel.refreshWallet()
                    if (!walletSession.registry.hasAnyWallet) onWalletRemoved()
                },
                onAddExisting = onAddExistingWallet,
                onCreateNew = onCreateWallet
            )
        }
    }
}

@Composable
private fun HomeBalanceSection(
    formattedBalance: String,
    balanceHidden: Boolean,
    isPullRefreshing: Boolean,
    balanceScale: Float,
    collapseProgress: Float,
    accountCaption: String,
    showsAccountCaption: Boolean,
    onToggleVisibility: () -> Unit
) {
    val amountSize = (52 - collapseProgress * 30).sp
    val usdtSize = (22 - collapseProgress * 8).sp

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth()
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            BalancePrivacyEyeButton(
                balanceHidden = balanceHidden,
                isPullRefreshing = isPullRefreshing,
                onToggle = onToggleVisibility
            )

            Row(
                modifier = Modifier
                    .clickable(onClick = onToggleVisibility)
                    .graphicsLayer {
                        scaleX = balanceScale
                        scaleY = balanceScale
                    },
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = formattedBalance,
                    style = MeshTypography.BalanceHero.copy(fontSize = amountSize),
                    color = if (balanceHidden) MeshColors.TextTertiary else MeshColors.HomeTextPrimary,
                    maxLines = 1,
                    modifier = Modifier.meshBalancePrivacyBlur(
                        isHidden = balanceHidden,
                        blurRadius = 8.dp
                    )
                )
                Text(
                    text = "USDT",
                    style = MeshTypography.Secondary.copy(
                        fontSize = usdtSize,
                        fontWeight = FontWeight.Light
                    ),
                    color = MeshColors.HomeTextSecondary,
                    modifier = Modifier
                        .padding(bottom = 6.dp)
                        .meshBalancePrivacyBlur(isHidden = balanceHidden)
                )
            }
        }

        if (showsAccountCaption) {
            Text(
                text = accountCaption,
                style = MeshTypography.Label.copy(fontSize = 11.sp, fontWeight = FontWeight.Light),
                color = MeshColors.TextTertiary,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(top = 1.dp)
                    .fillMaxWidth()
                    .meshBalancePrivacyBlur(isHidden = balanceHidden)
            )
        }
    }
}

@Composable
private fun BalancePrivacyEyeButton(
    balanceHidden: Boolean,
    isPullRefreshing: Boolean,
    onToggle: () -> Unit
) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .clickable(onClick = onToggle),
        contentAlignment = Alignment.Center
    ) {
        if (isPullRefreshing) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = MeshColors.HomeTextSecondary
            )
        } else {
            Icon(
                imageVector = if (balanceHidden) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                contentDescription = if (balanceHidden) "Show balance" else "Hide balance",
                tint = MeshColors.HomeTextSecondary,
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

@Composable
private fun HomeHeader(
    walletName: String,
    showsMulti: Boolean,
    walletTotal: String,
    balanceHidden: Boolean,
    onDrawer: () -> Unit,
    onWalletPicker: () -> Unit,
    onSecurity: () -> Unit
) {
    val context = LocalContext.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(MeshMetrics.ChromeButtonSize)
                .background(MeshColors.HomeCircleButtonFill, CircleShape)
                .clickable(onClick = onDrawer),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(R.drawable.ic_subaccounts),
                contentDescription = "Accounts",
                modifier = Modifier.size(22.dp)
            )
        }
        Column(
            modifier = Modifier.weight(1f).clickable(onClick = onWalletPicker),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    walletName,
                    style = MeshTypography.SectionTitle.copy(fontWeight = FontWeight.Medium),
                    color = MeshColors.HomeTextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                IconDown()
            }
            if (showsMulti) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.meshBalancePrivacyBlur(isHidden = balanceHidden)
                ) {
                    Text(
                        L10n.Wallet.homeTotalAmountLabel(context),
                        style = MeshTypography.Label.copy(fontSize = 11.sp, fontWeight = FontWeight.Light),
                        color = MeshColors.TextTertiary
                    )
                    Text(
                        "$walletTotal USDT",
                        style = MeshTypography.Label.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
                        color = MeshColors.TextTertiary
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .size(MeshMetrics.ChromeButtonSize)
                .background(MeshColors.HomeCircleButtonFill, CircleShape)
                .clickable(onClick = onSecurity),
            contentAlignment = Alignment.Center
        ) {
            Image(
                painter = painterResource(R.drawable.ic_gearshape),
                contentDescription = "Settings",
                modifier = Modifier.size(22.dp)
            )
        }
    }
}

@Composable
private fun IconDown() {
    Icon(
        Icons.Default.KeyboardArrowDown,
        contentDescription = null,
        tint = MeshColors.HomeTextSecondary,
        modifier = Modifier.size(18.dp)
    )
}

@Composable
private fun ActivityFilterBar(
    selected: ActivityFilter,
    onSelect: (ActivityFilter) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val labels = listOf(
        ActivityFilter.All to L10n.Wallet.filterAll(context),
        ActivityFilter.Received to L10n.Wallet.filterReceived(context),
        ActivityFilter.Sent to L10n.Wallet.filterSent(context)
    )
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        labels.forEach { (filter, label) ->
            val active = filter == selected
            Text(
                text = label,
                style = MeshTypography.Caption,
                color = if (active) MeshColors.TextPrimary else MeshColors.TextSecondary,
                modifier = Modifier
                    .background(
                        if (active) MeshWalletHomeColors.filterPillSelected.copy(alpha = 0.35f) else MeshColors.Surface,
                        RoundedCornerShape(20.dp)
                    )
                    .clickable { onSelect(filter) }
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}
