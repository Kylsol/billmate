//
//  GroupRepository.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Foundation
import FirebaseFirestore

final class GroupsRepository {

    private let db = Firestore.firestore()

    // MARK: - Fetch Active Groups
    func fetchActiveGroups(for userId: String) async throws -> [GroupDoc] {
        let snapshot = try await db.collection("groups")
            .whereField("memberUids", arrayContains: userId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()

        return try snapshot.documents.map { try $0.data(as: GroupDoc.self) }
    }

    // MARK: - Soft Delete
    func softDeleteGroup(
        groupId: String,
        deletedByUid: String,
        deletedByName: String
    ) async throws {

        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now)!

        try await db.collection("groups").document(groupId).updateData([
            "isDeleted": true,
            "deletedAt": Timestamp(date: now),
            "deleteExpiresAt": Timestamp(date: expires),
            "deletedByUid": deletedByUid,
            "deletedByName": deletedByName
        ])
    }

    // MARK: - Restore
    func restoreGroup(groupId: String) async throws {
        try await db.collection("groups").document(groupId).updateData([
            "isDeleted": false,
            "deletedAt": FieldValue.delete(),
            "deleteExpiresAt": FieldValue.delete(),
            "deletedByUid": FieldValue.delete(),
            "deletedByName": FieldValue.delete()
        ])
    }
}
