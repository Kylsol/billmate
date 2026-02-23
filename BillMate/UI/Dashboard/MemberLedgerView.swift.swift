//
//  MemberLedgerView.swift.swift
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

    var body: some View {
        List {
            if let err = dashVM.errorMessage {
                Text(err).foregroundStyle(.red)
            }

            if rows.isEmpty {
                Text("No transactions for \(memberName).")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
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
        .navigationTitle(memberName)
        .task { await reload() }
    }

    // MARK: - Data

    private func reload() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)
    }

    private var rows: [LedgerRow] {
        var out: [LedgerRow] = []

        // Bills that involve member:
        // - member is the payer OR member is a participant
        for b in dashVM.bills {
            let isInvolved = (b.paidByUid == memberUid) || b.participantUids.contains(memberUid)
            guard isInvolved else { continue }

            let payer = displayName(for: b.paidByUid)
            let title = b.description
            let subtitle = "Bill • Paid by \(payer)"
            out.append(LedgerRow(kind: .bill, id: b.id ?? UUID().uuidString, title: title, subtitle: subtitle, amount: b.amount, date: b.date))
        }

        // Payments that involve member:
        // If you added paidToUid, include either side.
        for p in dashVM.payments {
            let toUid = p.paidToUid
            let isInvolved =
                (p.paidByUid == memberUid) ||
                ((toUid ?? "").isEmpty == false && toUid == memberUid)

            guard isInvolved else { continue }

            let fromName = displayName(for: p.paidByUid)
            let subtitle: String
            if let to = toUid, !to.isEmpty {
                let toName = displayName(for: to)
                subtitle = "Payment • \(fromName) → \(toName)"
            } else {
                subtitle = "Payment • Paid by \(fromName)"
            }

            let title = p.note.isEmpty ? "Payment" : p.note
            out.append(LedgerRow(kind: .payment, id: p.id ?? UUID().uuidString, title: title, subtitle: subtitle, amount: p.amount, date: p.date))
        }

        // newest first
        return out.sorted { $0.date > $1.date }
    }

    private func displayName(for uid: String) -> String {
        if let m = dashVM.members.first(where: { $0.uid == uid }) {
            let trimmed = (m.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = m.email, !email.isEmpty { return email }
        }
        return uid
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
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
}
