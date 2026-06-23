import SwiftUI

struct WalletActivityListView: View {
    @ObservedObject var viewModel: WalletHomeViewModel
    var balanceHidden: Bool
    let onSelect: (WalletTransaction) -> Void
    let onClose: () -> Void

    @State private var activityFilter: WalletActivityFilter = .all

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        summaryStrip
                        filterBar

                        if viewModel.isLoading && viewModel.transactions.isEmpty {
                            loadingState
                        } else if viewModel.transactions.isEmpty {
                            emptyState
                        } else if filteredTransactions.isEmpty {
                            filteredEmptyState
                        } else {
                            groupedTransactions
                        }

                        if let loadError = viewModel.loadError {
                            Text(loadError)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(Color.orange)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await viewModel.load(transactionLimit: 50)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await viewModel.load(transactionLimit: 50)
        }
    }

    private var filteredTransactions: [WalletTransaction] {
        switch activityFilter {
        case .all:
            return viewModel.transactions
        case .received:
            return viewModel.transactions.filter(\.isIncoming)
        case .sent:
            return viewModel.transactions.filter { !$0.isIncoming }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                MeshChromeButton.close(action: onClose)
                Spacer()
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding - 8)

            MeshHairlineDivider()
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    private var filterBar: some View {
        WalletActivityFilterBar(selection: $activityFilter)
    }

    private var summaryStrip: some View {
        MeshInlineStatsRow(metrics: [
            (value: "\(filteredTransactions.count)", label: activityFilter == .all ? "Transfers" : "Shown"),
            (value: incomingCountText, label: "Received"),
            (value: sentCountText, label: "Sent"),
        ])
    }

    private var incomingCountText: String {
        "\(filteredTransactions.filter(\.isIncoming).count)"
    }

    private var sentCountText: String {
        "\(filteredTransactions.filter { !$0.isIncoming }.count)"
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
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(MeshTheme.Typography.icon(size: 32, weight: .thin))
                .foregroundStyle(MeshTheme.Colors.textTertiary)
            Text("No transfers yet")
                .font(MeshTheme.Typography.sans(size: 18, weight: .medium))
                .foregroundStyle(MeshTheme.Colors.textPrimary)
            Text("Incoming and outgoing USDT will appear here.")
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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

    private var groupedTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groupedByDay, id: \.day) { group in
                VStack(alignment: .leading, spacing: 0) {
                    MeshActivitySectionHeader(title: group.day)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, tx in
                        Button {
                            onSelect(tx)
                        } label: {
                            WalletTransactionRowView(
                                transaction: tx,
                                balanceHidden: balanceHidden,
                                style: .rich,
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

    private var groupedByDay: [(day: String, items: [WalletTransaction])] {
        filteredTransactions.groupedByDayLabel()
    }
}
