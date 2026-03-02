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

    /// Loads members, bills, and payments for the active home, then recomputes balances.
    ///
    /// IMPORTANT:
    /// - Bills and Payments support soft delete (Recycle Bin).
    /// - Dashboard should NOT include deleted docs in totals, so we filter them out here.
    /// - We filter client-side to avoid composite index requirements while you stabilize indexes.
    func loadAll(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            // --- Members ---
            let membersSnap = try await FirestoreService.membersCol(homeId).getDocuments()
            self.members = try membersSnap.documents.map { try $0.data(as: MemberDoc.self) }

            // --- Bills (load then filter out soft-deleted) ---
            let billsSnap = try await FirestoreService.billsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()

            let allBills = try billsSnap.documents.map { try $0.data(as: BillDoc.self) }
            self.bills = allBills.filter { ($0.isDeleted ?? false) == false }

            // --- Payments (load then filter out soft-deleted) ---
            let paymentsSnap = try await FirestoreService.paymentsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()

            let allPayments = try paymentsSnap.documents.map { try $0.data(as: PaymentDoc.self) }
            self.payments = allPayments.filter { ($0.isDeleted ?? false) == false }

            // --- Compute balances ---
            recompute()

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Compute Balances

    /// Recomputes member balances from the currently loaded ACTIVE bills/payments.
    func recompute() {
        self.balances = BalanceCalculator.compute(
            members: members,
            bills: bills,
            payments: payments
        )
    }
}
