import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class BillsViewModel: ObservableObject {
    @Published var bills: [BillDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // MARK: - Load (Active Bills Only)

    /// Loads ACTIVE bills (excludes soft-deleted bills).
    /// IMPORTANT: This requires bills to have `isDeleted` set to false when created,
    /// OR we handle missing field by filtering client-side as a fallback.
    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let snap = try await FirestoreService.billsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()

            let all = try snap.documents.map { try $0.data(as: BillDoc.self) }

            // Filter out soft-deleted bills locally (no composite index needed)
            self.bills = all.filter { ($0.isDeleted ?? false) == false }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add Bill

    /// Adds a new bill and ensures it is ACTIVE by default (`isDeleted = false`).
    func addBill(homeId: String, bill: BillDoc) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            // Ensure new bills are created as active (important for the active-only query).
            var toSave = bill
            toSave.isDeleted = false
            toSave.deletedAt = nil
            toSave.deleteExpiresAt = nil
            toSave.deletedByUid = nil
            toSave.deletedByName = nil

            let ref = try FirestoreService.billsCol(homeId).addDocument(from: toSave)

            // Optional admin event (use the created doc id)
            let event = EventDoc(
                id: nil,
                type: "bill_created",
                actorUid: bill.createdByUid,
                targetType: "bill",
                targetId: ref.documentID,
                message: "Bill added: \(bill.description)",
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
