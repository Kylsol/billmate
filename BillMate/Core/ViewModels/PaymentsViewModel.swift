//
//  PaymentsViewModel.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class PaymentsViewModel: ObservableObject {
    @Published var payments: [PaymentDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // MARK: - Load (Active Payments Only)

    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let activeSnap = try await FirestoreService.paymentsCol(homeId)
                .whereField("isDeleted", isEqualTo: false)
                .order(by: "date", descending: true)
                .getDocuments()

            var loaded = try activeSnap.documents.map { try $0.data(as: PaymentDoc.self) }

            if loaded.isEmpty {
                let snap = try await FirestoreService.paymentsCol(homeId)
                    .order(by: "date", descending: true)
                    .getDocuments()

                let all = try snap.documents.map { try $0.data(as: PaymentDoc.self) }
                loaded = all.filter { ($0.isDeleted ?? false) == false }
            }

            payments = loaded

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add Payment

    func addPayment(homeId: String, payment: PaymentDoc) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            var toSave = payment
            toSave.isDeleted = false
            toSave.deletedAt = nil
            toSave.deleteExpiresAt = nil
            toSave.deletedByUid = nil
            toSave.deletedByName = nil

            let ref = try FirestoreService.paymentsCol(homeId).addDocument(from: toSave)

            let event = EventDoc(
                id: nil,
                type: "payment_created",
                actorUid: payment.createdByUid,
                actorName: nil,
                targetType: "payment",
                targetId: ref.documentID,
                message: "Payment added: \(payment.note.isEmpty ? "Payment" : payment.note)",
                changedField: nil,
                oldValue: nil,
                newValue: nil,
                createdAt: Date()
            )
            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

            await load(homeId: homeId)

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Update Payment

    func updatePayment(
        homeId: String,
        originalPayment: PaymentDoc,
        amount: Double,
        note: String,
        date: Date,
        paidByUid: String,
        paidToUid: String,
        actorUid: String,
        actorName: String?
    ) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let paymentId = originalPayment.id else {
            errorMessage = "Missing payment ID."
            return false
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        guard amount >= 0 else {
            errorMessage = "Amount must be zero or greater."
            return false
        }

        guard !paidByUid.isEmpty else {
            errorMessage = "Select who paid."
            return false
        }

        guard !paidToUid.isEmpty else {
            errorMessage = "Select who received the payment."
            return false
        }

        guard paidByUid != paidToUid else {
            errorMessage = "Paid By and Paid To cannot be the same."
            return false
        }

        let detected = firstPaymentChange(
            original: originalPayment,
            newAmount: amount,
            newNote: trimmedNote,
            newDate: date,
            newPaidByUid: paidByUid,
            newPaidToUid: paidToUid
        )

        do {
            try await FirestoreService.paymentsCol(homeId)
                .document(paymentId)
                .updateData([
                    "amount": amount,
                    "note": trimmedNote,
                    "date": Timestamp(date: date),
                    "paidByUid": paidByUid,
                    "paidToUid": paidToUid,
                    "updatedAt": Timestamp(date: Date()),
                    "updatedByUid": actorUid
                ])

            let event = EventDoc(
                id: nil,
                type: "payment_updated",
                actorUid: actorUid,
                actorName: actorName,
                targetType: "payment",
                targetId: paymentId,
                message: "Updated: Payment to \(paidToUid) from \(paidByUid)",
                changedField: detected?.field,
                oldValue: detected?.oldValue,
                newValue: detected?.newValue,
                createdAt: Date()
            )
            _ = try? FirestoreService.eventsCol(homeId).addDocument(from: event)

            await load(homeId: homeId)
            return true

        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Change Detection

    private func firstPaymentChange(
        original: PaymentDoc,
        newAmount: Double,
        newNote: String,
        newDate: Date,
        newPaidByUid: String,
        newPaidToUid: String
    ) -> (field: String, oldValue: String, newValue: String)? {
        if original.amount != newAmount {
            return (
                "Amount",
                currencyString(original.amount),
                currencyString(newAmount)
            )
        }

        if original.note.trimmingCharacters(in: .whitespacesAndNewlines) != newNote {
            let oldNote = original.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                "Note",
                oldNote.isEmpty ? "No note" : oldNote,
                newNote.isEmpty ? "No note" : newNote
            )
        }

        if !Calendar.current.isDate(original.date, inSameDayAs: newDate) {
            return (
                "Date",
                dateString(original.date),
                dateString(newDate)
            )
        }

        if original.paidByUid != newPaidByUid {
            return (
                "Paid By",
                original.paidByUid,
                newPaidByUid
            )
        }

        if (original.paidToUid ?? "") != newPaidToUid {
            return (
                "Paid To",
                (original.paidToUid ?? "").isEmpty ? "Unknown" : (original.paidToUid ?? ""),
                newPaidToUid
            )
        }

        return nil
    }

    private func currencyString(_ amount: Double) -> String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return amount.formatted(.currency(code: code))
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
