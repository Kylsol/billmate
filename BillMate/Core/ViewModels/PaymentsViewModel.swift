import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class PaymentsViewModel: ObservableObject {
    @Published var payments: [PaymentDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let snap = try await FirestoreService.paymentsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()
            self.payments = try snap.documents.map { try $0.data(as: PaymentDoc.self) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPayment(homeId: String, payment: PaymentDoc) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try FirestoreService.paymentsCol(homeId).addDocument(from: payment)

            // Optional admin event
            let event = EventDoc(
                id: nil,
                type: "payment_created",
                actorUid: payment.createdByUid,
                targetType: "payment",
                targetId: payment.id ?? "",
                message: "Payment added: \(payment.note.isEmpty ? "Payment" : payment.note)",
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
