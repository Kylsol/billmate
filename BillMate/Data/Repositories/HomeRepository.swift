//
//  HomeRepository.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Foundation
import FirebaseFirestore

final class HomesRepository {

    private let db = Firestore.firestore()

    // MARK: - Fetch Active Homes
    func fetchActiveHomes(for userId: String) async throws -> [HomeDoc] {
        let snapshot = try await db.collection("homes")
            .whereField("memberUids", arrayContains: userId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        return try snapshot.documents.map { try $0.data(as: HomeDoc.self) }
    }

    // MARK: - Soft Delete
    func softDeleteHome(
        homeId: String,
        deletedByUid: String,
        deletedByName: String
    ) async throws {

        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)!

        try await db.collection("homes").document(homeId).updateData([
            "isDeleted": true,
            "deletedAt": Timestamp(date: now),
            "deleteExpiresAt": Timestamp(date: expires),
            "deletedByUid": deletedByUid,
            "deletedByName": deletedByName
        ])
    }

    // MARK: - Restore
    func restoreHome(homeId: String) async throws {
        try await db.collection("homes").document(homeId).updateData([
            "isDeleted": false,
            "deletedAt": FieldValue.delete(),
            "deleteExpiresAt": FieldValue.delete(),
            "deletedByUid": FieldValue.delete(),
            "deletedByName": FieldValue.delete()
        ])
    }
}
