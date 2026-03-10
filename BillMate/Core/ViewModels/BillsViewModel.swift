//
//  BillsViewModel.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class BillsViewModel: ObservableObject {
    @Published var bills: [BillDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // MARK: - Load (Active Bills Only)

    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let snap = try await FirestoreService.billsCol(homeId)
                .order(by: "date", descending: true)
                .getDocuments()

            let all = try snap.documents.map { try $0.data(as: BillDoc.self) }
            bills = all.filter { ($0.isDeleted ?? false) == false }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add Bill

    func addBill(homeId: String, bill: BillDoc) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            var toSave = bill
            toSave.isDeleted = false
            toSave.deletedAt = nil
            toSave.deleteExpiresAt = nil
            toSave.deletedByUid = nil
            toSave.deletedByName = nil

            let ref = try FirestoreService.billsCol(homeId).addDocument(from: toSave)

            let event = EventDoc(
                id: nil,
                type: "bill_created",
                actorUid: bill.createdByUid,
                actorName: nil,
                targetType: "bill",
                targetId: ref.documentID,
                message: "Bill added: \(bill.description)",
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

    // MARK: - Update Bill

    func updateBill(
        homeId: String,
        originalBill: BillDoc,
        description: String,
        amount: Double,
        date: Date,
        category: String,
        paidByUid: String,
        participantUids: [String],
        actorUid: String,
        actorName: String?
    ) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let billId = originalBill.id else {
            errorMessage = "Missing bill ID."
            return false
        }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDescription.isEmpty else {
            errorMessage = "Description is required."
            return false
        }

        guard amount >= 0 else {
            errorMessage = "Amount must be zero or greater."
            return false
        }

        guard !trimmedCategory.isEmpty else {
            errorMessage = "Category is required."
            return false
        }

        guard !paidByUid.isEmpty else {
            errorMessage = "Select who paid."
            return false
        }

        guard !participantUids.isEmpty else {
            errorMessage = "Select at least one participant."
            return false
        }

        let detected = firstBillChange(
            original: originalBill,
            newDescription: trimmedDescription,
            newAmount: amount,
            newDate: date,
            newCategory: trimmedCategory,
            newPaidByUid: paidByUid,
            newParticipantUids: participantUids
        )

        do {
            try await FirestoreService.billsCol(homeId)
                .document(billId)
                .updateData([
                    "description": trimmedDescription,
                    "amount": amount,
                    "date": Timestamp(date: date),
                    "category": trimmedCategory,
                    "paidByUid": paidByUid,
                    "participantUids": participantUids,
                    "updatedAt": Timestamp(date: Date()),
                    "updatedByUid": actorUid
                ])

            let targetCategory = trimmedCategory.isEmpty ? "Other" : trimmedCategory
            let event = EventDoc(
                id: nil,
                type: "bill_updated",
                actorUid: actorUid,
                actorName: actorName,
                targetType: "bill",
                targetId: billId,
                message: "Updated: Bill for \(targetCategory)",
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

    private func firstBillChange(
        original: BillDoc,
        newDescription: String,
        newAmount: Double,
        newDate: Date,
        newCategory: String,
        newPaidByUid: String,
        newParticipantUids: [String]
    ) -> (field: String, oldValue: String, newValue: String)? {
        if normalizedCategory(original.category) != newCategory {
            return (
                "Category",
                normalizedCategory(original.category),
                newCategory
            )
        }

        if original.description.trimmingCharacters(in: .whitespacesAndNewlines) != newDescription {
            return (
                "Description",
                original.description,
                newDescription
            )
        }

        if original.amount != newAmount {
            return (
                "Amount",
                currencyString(original.amount),
                currencyString(newAmount)
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

        if Set(original.participantUids) != Set(newParticipantUids) {
            return (
                "Participants",
                "\(original.participantUids.count) selected",
                "\(newParticipantUids.count) selected"
            )
        }

        return nil
    }

    private func normalizedCategory(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
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
