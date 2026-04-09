//
//  ConsolidateView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/10/26.
//

import SwiftUI

struct ConsolidateView: View {
    let members: [MemberDoc]
    let bills: [BillDoc]
    let payments: [PaymentDoc]
    let currencyCode: String

    private var directDebts: [PairwiseDebt] {
        DirectDebtCalculator.compute(
            members: members,
            bills: bills,
            payments: payments
        )
    }

    var body: some View {
        List {
            if directDebts.isEmpty {
                ContentUnavailableView(
                    "Nothing to Show",
                    systemImage: "checkmark.circle",
                    description: Text("Nobody currently owes anyone anything.")
                )
            } else {
                Section("Who Owes Who") {
                    ForEach(directDebts) { debt in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center, spacing: 8) {
                                Text(debt.fromName)
                                    .font(.headline)

                                if isGuestName(debt.fromName) {
                                    guestBadge
                                }

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(debt.toName)
                                    .font(.headline)

                                if isGuestName(debt.toName) {
                                    guestBadge
                                }
                            }

                            HStack {
                                Text("\(displayNameWithoutGuestPrefix(debt.fromName)) owes \(displayNameWithoutGuestPrefix(debt.toName))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text(debt.amount, format: .currency(code: currencyCode))
                                    .font(.headline)
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Consolidate")
    }

    private var guestBadge: some View {
        Text("Guest")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
    }

    private func isGuestName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("guest:")
    }

    private func displayNameWithoutGuestPrefix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("guest:") {
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
