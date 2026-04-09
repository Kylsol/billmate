//
//  MemberLedgerView.swift
//  BillMate
//
//  Created by Kyle Solomons on 2/23/26.
//

import SwiftUI

struct MemberLedgerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var dashVM = DashboardViewModel()

    let memberUid: String
    let memberName: String

    @State private var filter: LedgerFilter = .all

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(LedgerFilter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let err = dashVM.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if filteredRows.isEmpty {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredRows) { row in
                    NavigationLink {
                        destinationView(for: row)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.title)
                                .font(.headline)

                            HStack {
                                Text(row.amount, format: .currency(code: currencyCode()))
                                    .monospacedDigit()
                                Spacer()
                                Text(row.date, style: .date)
                                    .foregroundStyle(.secondary)
                            }

                            Text(row.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(memberName)
        .navigationBarTitleDisplayMode(.large)
        .task { await reload() }
    }

    // MARK: - Data

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)
    }

    private var rows: [LedgerRow] {
        var out: [LedgerRow] = []

        for bill in dashVM.bills {
            let isInvolved = isMemberInvolved(in: bill)
            guard isInvolved else { continue }

            let payer = displayName(for: bill.paidByUid)
            let title = bill.description
            let subtitle = billLedgerSubtitle(for: bill, payer: payer)

            out.append(
                LedgerRow(
                    kind: .bill,
                    id: bill.id ?? UUID().uuidString,
                    title: title,
                    subtitle: subtitle,
                    amount: bill.amount,
                    date: bill.date,
                    bill: bill,
                    payment: nil
                )
            )
        }

        for payment in dashVM.payments {
            let toUid = payment.paidToUid
            let isInvolved =
                (payment.paidByUid == memberUid) ||
                ((toUid ?? "").isEmpty == false && toUid == memberUid)

            guard isInvolved else { continue }

            let fromName = displayName(for: payment.paidByUid)
            let subtitle: String
            if let to = toUid, !to.isEmpty {
                let toName = displayName(for: to)
                subtitle = "Payment • \(fromName) → \(toName)"
            } else {
                subtitle = "Payment • Paid by \(fromName)"
            }

            let title = payment.note.isEmpty ? "Payment" : payment.note

            out.append(
                LedgerRow(
                    kind: .payment,
                    id: payment.id ?? UUID().uuidString,
                    title: title,
                    subtitle: subtitle,
                    amount: payment.amount,
                    date: payment.date,
                    bill: nil,
                    payment: payment
                )
            )
        }

        return out.sorted { $0.date > $1.date }
    }

    private var filteredRows: [LedgerRow] {
        switch filter {
        case .all:
            return rows
        case .bills:
            return rows.filter { $0.kind == .bill }
        case .payments:
            return rows.filter { $0.kind == .payment }
        }
    }

    private var emptyStateText: String {
        switch filter {
        case .all:
            return "No transactions for \(memberName)."
        case .bills:
            return "No bills for \(memberName)."
        case .payments:
            return "No payments for \(memberName)."
        }
    }

    @ViewBuilder
    private func destinationView(for row: LedgerRow) -> some View {
        switch row.kind {
        case .bill:
            if let bill = row.bill {
                BillDetailView(
                    bill: bill,
                    isRecycleBinItem: false,
                    onChanged: {
                        Task { await reload() }
                    }
                )
            } else {
                Text("Bill not found.")
                    .foregroundStyle(.secondary)
            }

        case .payment:
            if let payment = row.payment {
                PaymentDetailView(
                    payment: payment,
                    isRecycleBinItem: false,
                    onChanged: {
                        Task { await reload() }
                    }
                )
            } else {
                Text("Payment not found.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bill involvement

    private func isMemberInvolved(in bill: BillDoc) -> Bool {
        if bill.paidByUid == memberUid {
            return true
        }

        if let splitEntries = bill.splitEntries, !splitEntries.isEmpty {
            return splitEntries.contains { entry in
                entry.uid == memberUid
            }
        }

        return bill.participantUids.contains(memberUid)
    }

    private func billLedgerSubtitle(for bill: BillDoc, payer: String) -> String {
        if let splitEntries = bill.splitEntries, !splitEntries.isEmpty {
            let participantNames = splitEntries.map { splitEntryDisplayName($0) }
            let summary = participantNames.joined(separator: ", ")
            return "Bill • Paid by \(payer) • Split with \(summary)"
        }

        return "Bill • Paid by \(payer)"
    }

    private func splitEntryDisplayName(_ entry: BillSplitEntry) -> String {
        if let uid = entry.uid, !uid.isEmpty {
            return displayName(for: uid)
        }

        let trimmed = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Guest" : trimmed
    }

    private func displayName(for uid: String) -> String {
        if let member = dashVM.members.first(where: { $0.uid == uid }) {
            let trimmed = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = member.email, !email.isEmpty { return email }
        }

        if uid.hasPrefix("guest:") {
            return uid.replacingOccurrences(of: "guest:", with: "")
        }

        return uid
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
}

// MARK: - Filter

private enum LedgerFilter: String, CaseIterable {
    case all = "All"
    case bills = "Bills"
    case payments = "Payments"
}

// MARK: - Row model

private struct LedgerRow: Identifiable {
    enum Kind { case bill, payment }

    let kind: Kind
    let id: String
    let title: String
    let subtitle: String
    let amount: Double
    let date: Date

    let bill: BillDoc?
    let payment: PaymentDoc?
}
