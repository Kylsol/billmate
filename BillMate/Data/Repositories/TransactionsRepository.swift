//
//  TransactionsRRepository.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Foundation
import FirebaseFirestore

final class TransactionsRepository {
    private let db = Firestore.firestore()

    private func txCol(homeId: String) -> CollectionReference {
        db.collection("homes").document(homeId).collection("transactions")
    }

    // Active transactions (normal list)
    func fetchActiveTransactions(homeId: String) async throws -> [BillDoc] {
        let snap = try await txCol(homeId: homeId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        return try snap.documents.map { try $0.data(as: BillDoc.self) }
    }

    // Deleted transactions for recycle bin (per home)
    func fetchDeletedTransactions(homeId: String) async throws -> [BillDoc] {
        let snap = try await txCol(homeId: homeId)
            .whereField("isDeleted", isEqualTo: true)
            .getDocuments()

        return try snap.documents.map { try $0.data(as: BillDoc.self) }
    }

    // Soft delete
    func softDeleteTransaction(
        homeId: String,
        transactionId: String,
        deletedByUid: String,
        deletedByName: String
    ) async throws {
        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)!

        try await txCol(homeId: homeId)
            .document(transactionId)
            .updateData([
                "isDeleted": true,
                "deletedAt": Timestamp(date: now),
                "deleteExpiresAt": Timestamp(date: expires),
                "deletedByUid": deletedByUid,
                "deletedByName": deletedByName
            ])
    }

    // Restore
    func restoreTransaction(homeId: String, transactionId: String) async throws {
        try await txCol(homeId: homeId)
            .document(transactionId)
            .updateData([
                "isDeleted": false,
                "deletedAt": FieldValue.delete(),
                "deleteExpiresAt": FieldValue.delete(),
                "deletedByUid": FieldValue.delete(),
                "deletedByName": FieldValue.delete()
            ])
    }
}
