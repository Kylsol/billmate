//
//  MembersRepository.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Foundation
import FirebaseFirestore

final class MembersRepository {
    private let db = Firestore.firestore()

    private func membersCol(homeId: String) -> CollectionReference {
        db.collection("homes").document(homeId).collection("members")
    }

    func fetchMembers(homeId: String) async throws -> [MemberDoc] {
        let snap = try await membersCol(homeId: homeId).getDocuments()
        return try snap.documents.map { try $0.data(as: MemberDoc.self) }
    }

    func setMemberRole(homeId: String, memberUid: String, role: MemberRole) async throws {
        try await membersCol(homeId: homeId)
            .document(memberUid) // common pattern: doc id == uid
            .updateData([
                "role": role.rawValue
            ])
    }

    func removeMember(homeId: String, memberUid: String) async throws {
        try await membersCol(homeId: homeId)
            .document(memberUid)
            .delete()
    }
}
