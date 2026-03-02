import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class PaymentsViewModel: ObservableObject {
    @Published var payments: [PaymentDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // MARK: - Load (Active Payments Only)

    /// Loads ACTIVE payments (excludes soft-deleted payments).
    /// IMPORTANT:
    /// - If older Payment docs don't have `isDeleted`, the active-only query won't return them.
    /// - We include a fallback fetch + filter until your data is fully migrated.
    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            // Preferred: query only active docs
            let activeSnap = try await FirestoreService.paymentsCol(homeId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "date", descending: true)
                .getDocuments()

            var loaded = try activeSnap.documents.map { try $0.data(as: PaymentDoc.self) }

            // Fallback: if no docs returned (likely because older docs are missing isDeleted)
            if loaded.isEmpty {
                let snap = try await FirestoreService.paymentsCol(homeId)
                    .order(by: "date", descending: true)
                    .getDocuments()

                let all = try snap.documents.map { try $0.data(as: PaymentDoc.self) }

                // This filter only compiles if PaymentDoc has `isDeleted`.
                // If your PaymentDoc doesn't have it yet, update the model to match bills.
                loaded = all.filter { ($0.isDeleted ?? false) == false }
            }

            self.payments = loaded

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add Payment

    /// Adds a new payment and ensures it is ACTIVE by default (`isDeleted = false`).
    /// This keeps it compatible with the active-only query.
    func addPayment(homeId: String, payment: PaymentDoc) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            // Ensure new payments are active by default.
            // NOTE: This requires PaymentDoc to have these optional fields (recommended).
            var toSave = payment
            toSave.isDeleted = false
            toSave.deletedAt = nil
            toSave.deleteExpiresAt = nil
            toSave.deletedByUid = nil
            toSave.deletedByName = nil

            let ref = try FirestoreService.paymentsCol(homeId).addDocument(from: toSave)

            // Optional admin event (use created doc id)
            let event = EventDoc(
                id: nil,
                type: "payment_created",
                actorUid: payment.createdByUid,
                targetType: "payment",
                targetId: ref.documentID,
                message: "Payment added: \(payment.note.isEmpty ? "Payment" : payment.note)",
                createdAt: Date()
            )
            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

            await load(homeId: homeId)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers (currently unused here)

    private func displayName(for uid: String, members: [MemberDoc]) -> String {
        if let m = members.first(where: { $0.uid == uid }) {
            let trimmed = (m.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if let email = m.email, !email.isEmpty { return email }
        }
        return uid
    }
}
