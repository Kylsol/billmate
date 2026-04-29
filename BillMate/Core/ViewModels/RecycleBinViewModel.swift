    import Foundation
    import Combine
    import FirebaseFirestore

    @MainActor
    final class RecycleBinViewModel: ObservableObject {
        @Published var deletedGroups: [GroupDoc] = []
        @Published var deletedBills: [BillDoc] = []
        @Published var deletedPayments: [PaymentDoc] = []
        @Published var errorMessage: String?
        @Published var isBusy: Bool = false

        func load(groupId: String) async {
            errorMessage = nil
            isBusy = true
            defer { isBusy = false }

            do {
                async let groupsTask = loadDeletedGroup(groupId: groupId)
                async let billsTask = loadDeletedBills(groupId: groupId)
                async let paymentsTask = loadDeletedPayments(groupId: groupId)

                let (groups, bills, payments) = try await (groupsTask, billsTask, paymentsTask)

                deletedGroups = groups
                deletedBills = bills
                deletedPayments = payments
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        func restoreGroup(_ group: GroupDoc, appState: AppState) async {
            guard let groupId = group.id else {
                errorMessage = "Missing group ID."
                return
            }

            errorMessage = nil

            do {
                try await FirestoreService.groupRef(groupId).updateData([
                    "isDeleted": false,
                    "deletedAt": FieldValue.delete(),
                    "deleteExpiresAt": FieldValue.delete(),
                    "deletedByUid": FieldValue.delete(),
                    "deletedByName": FieldValue.delete()
                ])

                deletedGroups.removeAll { $0.id == groupId }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        func restoreBill(_ bill: BillDoc, appState: AppState) async {
            guard let activeGroupId = appState.activeGroup?.id,
                  let billId = bill.id else {
                errorMessage = "Missing bill ID."
                return
            }

            errorMessage = nil

            do {
                try await FirestoreService.billsCol(activeGroupId)
                    .document(billId)
                    .updateData([
                        "isDeleted": false,
                        "deletedAt": FieldValue.delete(),
                        "deleteExpiresAt": FieldValue.delete(),
                        "deletedByUid": FieldValue.delete(),
                        "deletedByName": FieldValue.delete()
                    ])

                deletedBills.removeAll { $0.id == billId }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        func restorePayment(_ payment: PaymentDoc, appState: AppState) async {
            guard let activeGroupId = appState.activeGroup?.id,
                  let paymentId = payment.id else {
                errorMessage = "Missing payment ID."
                return
            }

            errorMessage = nil

            do {
                try await FirestoreService.paymentsCol(activeGroupId)
                    .document(paymentId)
                    .updateData([
                        "isDeleted": false,
                        "deletedAt": FieldValue.delete(),
                        "deleteExpiresAt": FieldValue.delete(),
                        "deletedByUid": FieldValue.delete(),
                        "deletedByName": FieldValue.delete()
                    ])

                deletedPayments.removeAll { $0.id == paymentId }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        private func loadDeletedGroup(groupId: String) async throws -> [GroupDoc] {
            let snap = try await FirestoreService.groupRef(groupId).getDocument()
            guard let data = snap.data() else { return [] }

            let isDeleted = data["isDeleted"] as? Bool ?? false
            guard isDeleted else { return [] }

            let group = GroupDoc(
                id: snap.documentID,
                name: data["name"] as? String ?? "Group",
                createdAt: Self.dateFromAny(data["createdAt"]) ?? Date(),
                createdByUid: data["createdByUid"] as? String ?? ""
            )

            return [group]
        }

        private func loadDeletedBills(groupId: String) async throws -> [BillDoc] {
            let snap = try await FirestoreService.billsCol(groupId).getDocuments()
            return snap.documents.compactMap { document in
                let data = document.data()

                let id = document.documentID
                let description = data["description"] as? String ?? "Bill"
                let amount = data["amount"] as? Double ?? 0
                let date = Self.dateFromAny(data["date"]) ?? Date()
                let paidByUid = data["paidByUid"] as? String ?? ""
                let participantUids = data["participantUids"] as? [String] ?? []
                let createdAt = Self.dateFromAny(data["createdAt"]) ?? Date()
                let createdByUid = data["createdByUid"] as? String ?? ""

                let updatedAt = Self.dateFromAny(data["updatedAt"])
                let updatedByUid = data["updatedByUid"] as? String

                let isDeleted = data["isDeleted"] as? Bool
                let deletedAt = Self.dateFromAny(data["deletedAt"])
                let deleteExpiresAt = Self.dateFromAny(data["deleteExpiresAt"])
                let deletedByUid = data["deletedByUid"] as? String
                let deletedByName = data["deletedByName"] as? String

                let bill = BillDoc(
                    id: id,
                    description: description,
                    amount: amount,
                    date: date,
                    paidByUid: paidByUid,
                    participantUids: participantUids,
                    createdAt: createdAt,
                    createdByUid: createdByUid,
                    updatedAt: updatedAt,
                    updatedByUid: updatedByUid,
                    isDeleted: isDeleted,
                    deletedAt: deletedAt,
                    deleteExpiresAt: deleteExpiresAt,
                    deletedByUid: deletedByUid,
                    deletedByName: deletedByName
                )

                return (bill.isDeleted ?? false) ? bill : nil
            }
            .sorted { $0.date > $1.date }
        }

        private func loadDeletedPayments(groupId: String) async throws -> [PaymentDoc] {
            let snap = try await FirestoreService.paymentsCol(groupId).getDocuments()
            return snap.documents.compactMap { document in
                let data = document.data()

                let id = document.documentID
                let amount = data["amount"] as? Double ?? 0
                let date = Self.dateFromAny(data["date"]) ?? Date()
                let note = data["note"] as? String ?? ""
                let paidByUid = data["paidByUid"] as? String ?? ""
                let paidToUid = data["paidToUid"] as? String
                let createdAt = Self.dateFromAny(data["createdAt"]) ?? Date()
                let createdByUid = data["createdByUid"] as? String ?? ""

                let updatedAt = Self.dateFromAny(data["updatedAt"])
                let updatedByUid = data["updatedByUid"] as? String

                let isDeleted = data["isDeleted"] as? Bool
                let deletedAt = Self.dateFromAny(data["deletedAt"])
                let deleteExpiresAt = Self.dateFromAny(data["deleteExpiresAt"])
                let deletedByUid = data["deletedByUid"] as? String
                let deletedByName = data["deletedByName"] as? String

                let payment = PaymentDoc(
                    id: id,
                    amount: amount,
                    date: date,
                    note: note,
                    paidByUid: paidByUid,
                    paidToUid: paidToUid,
                    createdAt: createdAt,
                    createdByUid: createdByUid,
                    updatedAt: updatedAt,
                    updatedByUid: updatedByUid,
                    isDeleted: isDeleted,
                    deletedAt: deletedAt,
                    deleteExpiresAt: deleteExpiresAt,
                    deletedByUid: deletedByUid,
                    deletedByName: deletedByName
                )

                return (payment.isDeleted ?? false) ? payment : nil
            }
            .sorted { $0.date > $1.date }
        }

        private static func dateFromAny(_ value: Any?) -> Date? {
            if let ts = value as? Timestamp { return ts.dateValue() }
            if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
            if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
            return nil
        }
    }
