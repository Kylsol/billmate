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
            self.bills = try billsSnap.documents.map { try $0.data(as: BillDoc.self) }

            let paymentsSnap = try await FirestoreService.paymentsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()
            self.payments = try paymentsSnap.documents.map { try $0.data(as: PaymentDoc.self) }

            recompute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recompute() {
        self.balances = BalanceCalculator.compute(members: members, bills: bills, payments: payments)
    }
}
