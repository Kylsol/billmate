//
//  DirectDebtCalculator.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/18/26.
//

import Foundation

struct PairwiseDebt: Identifiable, Hashable {
    let id = UUID()
    let fromName: String
    let toName: String
    let amount: Double
}

enum DirectDebtCalculator {

    static func compute(
        members: [MemberDoc],
        bills: [BillDoc],
        payments: [PaymentDoc]
    ) -> [PairwiseDebt] {

        let tolerance = 0.01

        // ledger[from][to] = amount that "from" owes "to"
        var ledger: [String: [String: Double]] = [:]

        // unified participant names for members + guests
        var namesById: [String: String] = [:]

        for member in members {
            namesById[member.uid] = displayName(for: member)
        }

        func addDebt(from: String, to: String, amount: Double) {
            guard from != to else { return }
            guard amount > tolerance else { return }
            ledger[from, default: [:]][to, default: 0] += amount
        }

        // MARK: - Bills

        for bill in bills {
            let payerId = bill.paidByUid
            if namesById[payerId] == nil {
                namesById[payerId] = payerId
            }

            if let splitEntries = bill.splitEntries, !splitEntries.isEmpty {
                // New split system
                for entry in splitEntries {
                    let participantId = participantIdentifier(for: entry)

                    namesById[participantId] = normalizedName(
                        entry.name,
                        fallback: participantId
                    )

                    guard participantId != payerId else { continue }

                    let shareAmount = resolvedShareAmount(
                        entry: entry,
                        billTotal: bill.amount
                    )

                    addDebt(
                        from: participantId,
                        to: payerId,
                        amount: shareAmount
                    )
                }
            } else {
                // Legacy fallback
                let participants = Array(Set(bill.participantUids))
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

                guard !participants.isEmpty else { continue }

                let splitAmount = bill.amount / Double(participants.count)

                for participantUid in participants {
                    if namesById[participantUid] == nil {
                        namesById[participantUid] = participantUid
                    }

                    guard participantUid != payerId else { continue }

                    addDebt(
                        from: participantUid,
                        to: payerId,
                        amount: splitAmount
                    )
                }
            }
        }

        // MARK: - Payments

        for payment in payments {
            let from = payment.paidByUid

            guard let to = payment.paidToUid,
                  !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  from != to
            else { continue }

            if namesById[from] == nil { namesById[from] = from }
            if namesById[to] == nil { namesById[to] = to }

            var remainingPayment = payment.amount

            if let existing = ledger[from]?[to], existing > tolerance {
                let applied = min(existing, remainingPayment)
                let newAmount = existing - applied
                remainingPayment -= applied

                if newAmount <= tolerance {
                    ledger[from]?[to] = nil
                } else {
                    ledger[from]?[to] = newAmount
                }
            }

            if remainingPayment > tolerance {
                addDebt(
                    from: to,
                    to: from,
                    amount: remainingPayment
                )
            }
        }

        // MARK: - Pairwise Netting

        let participantIds = Array(namesById.keys).sorted()

        for from in participantIds {
            for to in participantIds {
                if from >= to { continue }

                let forward = ledger[from]?[to] ?? 0
                let reverse = ledger[to]?[from] ?? 0

                if forward > tolerance && reverse > tolerance {
                    if forward > reverse {
                        ledger[from]?[to] = forward - reverse
                        ledger[to]?[from] = nil
                    } else if reverse > forward {
                        ledger[to]?[from] = reverse - forward
                        ledger[from]?[to] = nil
                    } else {
                        ledger[from]?[to] = nil
                        ledger[to]?[from] = nil
                    }
                }
            }
        }

        // MARK: - Convert to UI rows

        var results: [PairwiseDebt] = []

        for (fromId, targets) in ledger {
            for (toId, amount) in targets {
                guard amount > tolerance else { continue }

                results.append(
                    PairwiseDebt(
                        fromName: namesById[fromId] ?? fromId,
                        toName: namesById[toId] ?? toId,
                        amount: amount
                    )
                )
            }
        }

        return results.sorted {
            if $0.fromName == $1.fromName {
                return $0.toName < $1.toName
            }
            return $0.fromName < $1.fromName
        }
    }

    // MARK: - Helpers

    private static func participantIdentifier(for entry: BillSplitEntry) -> String {
        if let uid = entry.uid, !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return uid
        }

        return "guest:\(normalizedGuestKey(entry.name))"
    }

    private static func normalizedGuestKey(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? UUID().uuidString : trimmed
    }

    private static func resolvedShareAmount(entry: BillSplitEntry, billTotal: Double) -> Double {
        if let amount = entry.amount, amount > 0 {
            return amount
        }

        if let percentage = entry.percentage, percentage > 0 {
            return billTotal * (percentage / 100.0)
        }

        return 0
    }

    private static func displayName(for member: MemberDoc) -> String {
        let trimmedName = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }

        if let email = member.email, !email.isEmpty {
            return email
        }

        return member.uid
    }

    private static func normalizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
