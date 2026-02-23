import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class BillsViewModel: ObservableObject {
    @Published var bills: [BillDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let snap = try await FirestoreService.billsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()
            self.bills = try snap.documents.map { try $0.data(as: BillDoc.self) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addBill(homeId: String, bill: BillDoc) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try FirestoreService.billsCol(homeId).addDocument(from: bill)

            // Optional admin event
            let event = EventDoc(
                id: nil,
                type: "bill_created",
                actorUid: bill.createdByUid,
                targetType: "bill",
                targetId: bill.id ?? "",
                message: "Bill added: \(bill.description)",
                createdAt: Date()
            )
            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

            await load(homeId: homeId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func displayName(for uid: String, members: [MemberDoc]) -> String {
        if let m = members.first(where: { $0.uid == uid }) {
            let trimmed = (m.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = m.email, !email.isEmpty { return email }
        }
        return uid // fallback
    }
}
