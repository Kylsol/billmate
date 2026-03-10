//
//  DashboardViewModel.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var members: [MemberDoc] = []
    @Published var bills: [BillDoc] = []
    @Published var payments: [PaymentDoc] = []

    @Published var balances: [MemberBalance] = []

    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // MARK: - Load Everything Needed For Dashboard

    func loadAll(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let membersSnap = try await FirestoreService.membersCol(homeId).getDocuments()
            self.members = try membersSnap.documents.map { try $0.data(as: MemberDoc.self) }

            let billsSnap = try await FirestoreService.billsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()

            let allBills = try billsSnap.documents.map { try $0.data(as: BillDoc.self) }
            self.bills = allBills.filter { ($0.isDeleted ?? false) == false }

            let paymentsSnap = try await FirestoreService.paymentsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()

            let allPayments = try paymentsSnap.documents.map { try $0.data(as: PaymentDoc.self) }
            self.payments = allPayments.filter { ($0.isDeleted ?? false) == false }

            recompute()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Compute Balances

    func recompute() {
        self.balances = BalanceCalculator.compute(
            members: members,
            bills: bills,
            payments: payments
        )
    }

    // MARK: - Monthly Spending Chart

    func monthlySpendingByCategory(for uid: String, referenceDate: Date = Date()) -> [CategorySpend] {
        let calendar = Calendar.current

        return bills
            .filter { $0.paidByUid == uid }
            .filter { calendar.isDate($0.date, equalTo: referenceDate, toGranularity: .month) }
            .reduce(into: [String: Double]()) { partial, bill in
                let category = normalizedCategory(bill.category)
                partial[category, default: 0] += bill.amount
            }
            .map { CategorySpend(category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    func monthlyTotalSpent(for uid: String, referenceDate: Date = Date()) -> Double {
        monthlySpendingByCategory(for: uid, referenceDate: referenceDate)
            .reduce(0) { $0 + $1.amount }
    }

    private func normalizedCategory(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
    }
}

// MARK: - Chart Model

struct CategorySpend: Identifiable, Hashable {
    let category: String
    let amount: Double

    var id: String { category }
}
