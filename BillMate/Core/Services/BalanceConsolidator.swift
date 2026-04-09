//
//  BalanceConsolidator.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/10/26.
//

import Foundation

enum BalanceConsolidator {

    static func consolidate(from balances: [MemberBalance]) -> [ConsolidatedDebt] {

        let tolerance = 0.01

        var debtors: [(name: String, amount: Double)] = []
        var creditors: [(name: String, amount: Double)] = []

        for balance in balances {
            if balance.amountOwed > tolerance {
                debtors.append((name: balance.displayName, amount: balance.amountOwed))
            } else if balance.amountOwed < -tolerance {
                creditors.append((name: balance.displayName, amount: abs(balance.amountOwed)))
            }
        }

        var results: [ConsolidatedDebt] = []

        var debtorIndex = 0
        var creditorIndex = 0

        while debtorIndex < debtors.count && creditorIndex < creditors.count {
            let amount = min(
                debtors[debtorIndex].amount,
                creditors[creditorIndex].amount
            )

            results.append(
                ConsolidatedDebt(
                    fromName: debtors[debtorIndex].name,
                    toName: creditors[creditorIndex].name,
                    amount: amount
                )
            )

            debtors[debtorIndex].amount -= amount
            creditors[creditorIndex].amount -= amount

            if debtors[debtorIndex].amount <= tolerance {
                debtorIndex += 1
            }

            if creditors[creditorIndex].amount <= tolerance {
                creditorIndex += 1
            }
        }

        return results.filter { $0.amount > tolerance }
    }
}
