import Foundation

struct MemberBalance: Identifiable {
    let id: String // uid
    let displayName: String
    let amountOwed: Double
}

enum BalanceCalculator {
    /// Positive = owes money (red). Negative = is owed money (green).
    static func compute(
        members: [MemberDoc],
        bills: [BillDoc],
        payments: [PaymentDoc]
    ) -> [MemberBalance] {
        var totals: [String: Double] = [:]

        for m in members {
            totals[m.uid] = 0
        }

        for bill in bills {
            let participants = bill.participantUids
            let count = max(participants.count, 1)
            let share = bill.amount / Double(count)

            for uid in participants {
                totals[uid, default: 0] += share
            }
            totals[bill.paidByUid, default: 0] -= bill.amount
        }

        // Payments:
        // - NEW docs (with paidToUid): transfer balance from payer -> recipient
        // - OLD docs (no paidToUid): keep your old behavior (payer gets -credit)
        for payment in payments {
            if let to = payment.paidToUid, !to.isEmpty {
                totals[payment.paidByUid, default: 0] -= payment.amount
                totals[to, default: 0] += payment.amount
            } else {
                // Old data fallback (pre "paidToUid")
                totals[payment.paidByUid, default: 0] -= payment.amount
            }
        }

        let memberMap = Dictionary(uniqueKeysWithValues: members.map { ($0.uid, $0) })

        let balances = totals.map { (uid, owed) in
            let m = memberMap[uid]

            let rawName = m?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (rawName?.isEmpty == false)
                ? rawName!
                : (m?.email ?? "User")

            return MemberBalance(
                id: uid,
                displayName: displayName,
                amountOwed: owed
            )
        }

        return balances.sorted { $0.amountOwed > $1.amountOwed }
    }
}
