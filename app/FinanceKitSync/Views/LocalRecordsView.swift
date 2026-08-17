//
//  LocalRecordsView.swift
//  FinanceKitSync
//
import SwiftUI

struct LocalRecordsView: View {
    private enum RecordKind: String, CaseIterable, Identifiable {
        case transactions = "Transactions"
        case accounts = "Accounts"

        var id: Self { self }
    }

    @State private var snapshot: SyncEngine.LocalSnapshot?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selection = RecordKind.transactions
    @State private var searchText = ""

    private var filteredTransactions: [SyncEngine.LocalTransactionRecord] {
        guard let transactions = snapshot?.transactions else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return transactions }
        return transactions.filter { record in
            let transaction = record.transaction
            let wallet = transaction.metadata.wallet
            return transaction.payee.localizedCaseInsensitiveContains(query)
                || transaction.id.localizedCaseInsensitiveContains(query)
                || transaction.currency.localizedCaseInsensitiveContains(query)
                || wallet.accountDisplayName?.localizedCaseInsensitiveContains(query) == true
                || wallet.institutionName?.localizedCaseInsensitiveContains(query) == true
                || wallet.merchantName?.localizedCaseInsensitiveContains(query) == true
                || wallet.merchantCategoryCode?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var filteredAccounts: [SyncAccount] {
        guard let accounts = snapshot?.accounts else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return accounts }
        return accounts.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.institution.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.currency.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Picker("Record type", selection: $selection) {
                ForEach(RecordKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if isLoading && snapshot == nil {
                HStack {
                    Spacer()
                    ProgressView("Reading FinanceKit…")
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, snapshot == nil {
                ContentUnavailableView(
                    "Records unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .listRowBackground(Color.clear)
            } else if selection == .transactions {
                transactionRows
            } else {
                accountRows
            }
        }
        .navigationTitle("Local records")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search records")
        .refreshable { await load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            if snapshot == nil { await load() }
        }
    }

    @ViewBuilder
    private var transactionRows: some View {
        if filteredTransactions.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No transactions" : "No matches",
                systemImage: "creditcard",
                description: Text(searchText.isEmpty
                    ? "FinanceKit has no transactions available to this app."
                    : "Try a different search.")
            )
            .listRowBackground(Color.clear)
        } else {
            Section("\(filteredTransactions.count) transactions") {
                ForEach(filteredTransactions.reversed()) { record in
                    NavigationLink {
                        TransactionRecordDetail(record: record)
                    } label: {
                        TransactionRecordRow(record: record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var accountRows: some View {
        if filteredAccounts.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No accounts" : "No matches",
                systemImage: "building.columns",
                description: Text(searchText.isEmpty
                    ? "FinanceKit has no accounts available to this app."
                    : "Try a different search.")
            )
            .listRowBackground(Color.clear)
        } else {
            Section("\(filteredAccounts.count) accounts") {
                ForEach(filteredAccounts) { account in
                    NavigationLink {
                        AccountRecordDetail(account: account)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                            Text(account.institution)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(account.balance, format: .currency(code: account.currency))
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            snapshot = try await SyncEngine.loadLocalSnapshot()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct TransactionRecordRow: View {
    let record: SyncEngine.LocalTransactionRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.transaction.payee)
                    .lineLimit(1)
                Text(record.transaction.metadata.wallet.accountDisplayName ?? "Unknown account")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.transactionDate, format: .dateTime.month().day().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.transaction.amount, format: .currency(code: record.transaction.currency))
                .font(.callout.monospacedDigit())
        }
    }
}

private struct TransactionRecordDetail: View {
    let record: SyncEngine.LocalTransactionRecord

    private var transaction: SyncTransaction { record.transaction }
    private var wallet: WalletMetadata.WalletPayload { transaction.metadata.wallet }

    var body: some View {
        List {
            Section("Transaction") {
                LabeledContent("Description", value: transaction.payee)
                LabeledContent("Amount") {
                    Text(transaction.amount, format: .currency(code: transaction.currency))
                        .monospacedDigit()
                }
                LabeledContent("Date") {
                    Text(record.transactionDate, format: .dateTime.month().day().year().hour().minute())
                }
                LabeledContent("Status", value: transaction.status.capitalized)
                LabeledContent("Type", value: wallet.transactionType)
                LabeledContent("Credit/debit", value: wallet.creditDebitIndicator.capitalized)
            }

            Section("Merchant") {
                optionalRow("Merchant", wallet.merchantName)
                optionalRow("Original description", wallet.originalTransactionDescription)
                optionalRow("Category code", wallet.merchantCategoryCode)
                optionalRow("Category", wallet.merchantCategoryDescription)
            }

            Section("Account") {
                optionalRow("Name", wallet.accountDisplayName)
                optionalRow("Institution", wallet.institutionName)
                LabeledContent("Account ID", value: transaction.accountId)
            }

            if let foreignAmount = wallet.foreignAmount {
                Section("Foreign currency") {
                    LabeledContent("Amount", value: "\(foreignAmount.value) \(foreignAmount.currency)")
                    optionalRow("Exchange rate", wallet.foreignExchangeRate)
                }
            }

            Section("FinanceKit identifiers") {
                LabeledContent("Transaction ID", value: transaction.id)
                optionalRow("Posted date", wallet.postedDate)
            }
        }
        .navigationTitle(transaction.payee)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func optionalRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

private struct AccountRecordDetail: View {
    let account: SyncAccount

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Name", value: account.name)
                LabeledContent("Institution", value: account.institution)
                LabeledContent("Balance") {
                    Text(account.balance, format: .currency(code: account.currency))
                        .monospacedDigit()
                }
                LabeledContent("Currency", value: account.currency)
            }
            Section("FinanceKit identifier") {
                Text(account.id)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
