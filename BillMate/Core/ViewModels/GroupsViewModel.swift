import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class GroupsViewModel: ObservableObject {

    // MARK: - Published UI State

    /// Groups shown in the "Group selection" list (ACTIVE only, not deleted).
    @Published var groups: [GroupDoc] = []

    /// Any error text you want to show in alerts / inline UI.
    @Published var errorMessage: String?

    /// Use this to show a spinner / disable buttons while work runs.
    @Published var isBusy: Bool = false
    
    // MARK: - Leave Group (Safe)

    /// Attempts to leave a group with safety checks:
    /// - Cannot leave if you are the only member
    /// - Cannot leave if you are the only admin
    func leaveGroupSafely(appState: AppState, groupId: String) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return false
        }

        do {
            // Fetch all members of the group
            let membersSnap = try await FirestoreService.membersCol(groupId).getDocuments()
            let members = membersSnap.documents.compactMap {
                try? $0.data(as: MemberDoc.self)
            }

            // RULE 1: Cannot leave if only member
            if members.count <= 1 {
                errorMessage = "You cannot leave because you are the only member."
                return false
            }

            // Count admins
            let adminCount = members.filter { $0.role == .admin }.count

            // RULE 2: If you're admin and only admin, block leaving
            if let me = members.first(where: { $0.uid == user.uid }),
               me.role == .admin,
               adminCount <= 1 {
                errorMessage = "You are the only admin. Promote another member before leaving."
                return false
            }

            // Safe to leave — remove membership
            try await FirestoreService.membersCol(groupId)
                .document(user.uid)
                .delete()

            // Clear active selection
            if appState.activeGroup?.id == groupId {
                appState.activeGroup = nil
                appState.activeRole = .resident
            }

            await loadGroups(for: user.uid)
            return true

        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Load Groups (Active)

    /// Loads all groups the user belongs to (based on collectionGroup("members")),
    /// then fetches each group doc and filters out deleted groups.
    func loadGroups(for uid: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let db = FirestoreService.db

            // Find every membership doc where this user is a member
            let snap = try await db.collectionGroup("members")
                .whereField("uid", isEqualTo: uid)
                .getDocuments()

            var loaded: [GroupDoc] = []

            for doc in snap.documents {
                // doc = groups/{groupId}/members/{uid}
                guard let groupRef = doc.reference.parent.parent else { continue }

                let groupSnap = try await groupRef.getDocument()
                guard let data = groupSnap.data() else { continue }

                // Filter out soft-deleted groups.
                // NOTE: If "isDeleted" is missing, treat as false (active).
                let isDeleted = data["isDeleted"] as? Bool ?? false
                if isDeleted { continue }

                let group = GroupDoc(
                    id: groupRef.documentID,
                    name: data["name"] as? String ?? "Group",
                    createdAt: Self.dateFromAny(data["createdAt"]) ?? Date(),
                    createdByUid: data["createdByUid"] as? String ?? ""
                )

                loaded.append(group)
            }

            // Sort groups for nicer UI
            groups = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }


    // MARK: - Load Groups (Recycle Bin)

    /// Loads groups this user belongs to that are currently soft-deleted.
    /// You’ll use this in your future RecycleBinView.
    func loadDeletedGroups(for uid: String) async -> [GroupDoc] {
        errorMessage = nil

        do {
            let db = FirestoreService.db

            let snap = try await db.collectionGroup("members")
                .whereField("uid", isEqualTo: uid)
                .getDocuments()

            var loaded: [GroupDoc] = []

            for doc in snap.documents {
                guard let groupRef = doc.reference.parent.parent else { continue }

                let groupSnap = try await groupRef.getDocument()
                guard let data = groupSnap.data() else { continue }

                let isDeleted = data["isDeleted"] as? Bool ?? false
                if !isDeleted { continue }

                let group = GroupDoc(
                    id: groupRef.documentID,
                    name: data["name"] as? String ?? "Group",
                    createdAt: Self.dateFromAny(data["createdAt"]) ?? Date(),
                    createdByUid: data["createdByUid"] as? String ?? ""
                )

                loaded.append(group)
            }

            return loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }


    // MARK: - Members (Admin tools you already added)

    func loadMembers(groupId: String) async -> [MemberDoc] {
        do {
            let snap = try await FirestoreService.membersCol(groupId).getDocuments()
            return try snap.documents.map { try $0.data(as: MemberDoc.self) }
                .sorted { ($0.name ?? $0.email ?? $0.uid) < ($1.name ?? $1.email ?? $1.uid) }
        } catch {
            self.errorMessage = error.localizedDescription
            return []
        }
    }

    func setMemberRole(appState: AppState, groupId: String, memberUid: String, role: MemberRole) async throws {
        guard let currentUser = appState.authUser else {
            throw NSError(domain: "BillMate", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in."])
        }

        let membersRef = FirestoreService.membersCol(groupId)
        let currentUserRef = membersRef.document(currentUser.uid)
        let targetRef = membersRef.document(memberUid)

        // Verify current user is still admin
        let currentSnap = try await currentUserRef.getDocument()
        guard let currentData = currentSnap.data() else {
            throw NSError(domain: "BillMate", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Your membership was not found."])
        }

        let currentRole = MemberRole(rawValue: currentData["role"] as? String ?? "resident") ?? .resident
        guard currentRole == .admin else {
            throw NSError(domain: "BillMate", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "You no longer have admin privileges."])
        }

        // Load target member
        let targetSnap = try await targetRef.getDocument()
        guard let targetData = targetSnap.data() else {
            throw NSError(domain: "BillMate", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Target member was not found."])
        }

        let targetCurrentRole = MemberRole(rawValue: targetData["role"] as? String ?? "resident") ?? .resident

        // Prevent removing the last admin
        if targetCurrentRole == .admin && role != .admin {
            let allMembersSnap = try await membersRef.getDocuments()
            let adminCount = allMembersSnap.documents.filter {
                let raw = $0.data()["role"] as? String ?? "resident"
                return raw == MemberRole.admin.rawValue
            }.count

            if adminCount <= 1 {
                throw NSError(domain: "BillMate", code: 400,
                              userInfo: [NSLocalizedDescriptionKey: "This group must always have at least one admin."])
            }
        }

        try await targetRef.setData(["role": role.rawValue], merge: true)

        // Refresh local app role immediately if I changed myself
        if currentUser.uid == memberUid {
            await refreshMyRole(appState: appState, groupId: groupId)
        }
    }

    func removeMember(appState: AppState, groupId: String, memberUid: String) async throws {
        guard let currentUser = appState.authUser else {
            throw NSError(domain: "BillMate", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in."])
        }

        let membersRef = FirestoreService.membersCol(groupId)
        let currentUserRef = membersRef.document(currentUser.uid)
        let targetRef = membersRef.document(memberUid)

        // Verify current user is still admin
        let currentSnap = try await currentUserRef.getDocument()
        guard let currentData = currentSnap.data() else {
            throw NSError(domain: "BillMate", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Your membership was not found."])
        }

        let currentRole = MemberRole(rawValue: currentData["role"] as? String ?? "resident") ?? .resident
        guard currentRole == .admin else {
            throw NSError(domain: "BillMate", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "You no longer have admin privileges."])
        }

        // Load target member
        let targetSnap = try await targetRef.getDocument()
        guard let targetData = targetSnap.data() else {
            throw NSError(domain: "BillMate", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Target member was not found."])
        }

        let targetRole = MemberRole(rawValue: targetData["role"] as? String ?? "resident") ?? .resident

        // Prevent removing the last admin
        if targetRole == .admin {
            let allMembersSnap = try await membersRef.getDocuments()
            let adminCount = allMembersSnap.documents.filter {
                let raw = $0.data()["role"] as? String ?? "resident"
                return raw == MemberRole.admin.rawValue
            }.count

            if adminCount <= 1 {
                throw NSError(domain: "BillMate", code: 400,
                              userInfo: [NSLocalizedDescriptionKey: "This group must always have at least one admin."])
            }
        }

        try await targetRef.delete()
    }


    // MARK: - Leave Group (Non-admin "I want out" action)

    /// Removes the current user from the group (does NOT delete the group).
    /// After leaving, refresh your groups list.
    func leaveGroup(appState: AppState, groupId: String) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return false
        }

        do {
            try await FirestoreService.membersCol(groupId)
                .document(user.uid)
                .delete()

            // If the user was actively viewing this group, clear it.
            if appState.activeGroup?.id == groupId {
                appState.activeGroup = nil
                appState.activeRole = .resident
            }

            await loadGroups(for: user.uid)
            return true

        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }


    // MARK: - Soft Delete Group (Moves to recycle bin for 30 days)

    /// Soft deletes a group by marking it deleted and setting an expiration date.
    /// There is NO permanent delete button in the app — purge should happen via backend expiry.
    func softDeleteGroup(appState: AppState, groupId: String) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return false
        }

        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now.addingTimeInterval(30 * 24 * 3600)

        do {
            try await FirestoreService.groupRef(groupId).setData([
                "isDeleted": true,
                "deletedAt": Timestamp(date: now),
                "deleteExpiresAt": Timestamp(date: expires),
                "deletedByUid": user.uid,
                "deletedByName": user.name as Any
            ], merge: true)

            // If user is currently in that group, kick them out of active selection.
            if appState.activeGroup?.id == groupId {
                appState.activeGroup = nil
                appState.activeRole = .resident
            }

            await loadGroups(for: user.uid)
            return true

        } catch {
            errorMessage = error.localizedCaseInsensitiveDescription
            return false
        }
    }

    /// Restore a group from the recycle bin.
    func restoreGroup(appState: AppState, groupId: String) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return false
        }

        do {
            try await FirestoreService.groupRef(groupId).setData([
                "isDeleted": false,
                "deletedAt": FieldValue.delete(),
                "deleteExpiresAt": FieldValue.delete(),
                "deletedByUid": FieldValue.delete(),
                "deletedByName": FieldValue.delete()
            ], merge: true)

            await loadGroups(for: user.uid)
            return true

        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }


    // MARK: - Select Group

    func selectGroup(appState: AppState, uid: String, groupId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let groupSnap = try await FirestoreService.groupRef(groupId).getDocument()
            guard let groupData = groupSnap.data() else {
                throw NSError(domain: "BillMate", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Group not found."])
            }

            // Optional: prevent selecting deleted group
            let isDeleted = groupData["isDeleted"] as? Bool ?? false
            if isDeleted {
                throw NSError(domain: "BillMate", code: 400,
                              userInfo: [NSLocalizedDescriptionKey: "This group is in the Recycle Bin. Restore it to use it."])
            }

            let memberSnap = try await FirestoreService
                .membersCol(groupId)
                .document(uid)
                .getDocument()

            guard let memberData = memberSnap.data() else {
                throw NSError(domain: "BillMate", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Membership not found."])
            }

            let group = GroupDoc(
                id: groupId,
                name: groupData["name"] as? String ?? "Group",
                createdAt: Self.dateFromAny(groupData["createdAt"]) ?? Date(),
                createdByUid: groupData["createdByUid"] as? String ?? ""
            )

            let roleStr = memberData["role"] as? String ?? "resident"

            appState.activeGroup = group
            appState.activeRole = Role(rawValue: roleStr) ?? .resident

        } catch {
            errorMessage = error.localizedDescription
        }
    }


    // MARK: - Create Invite

    func createInvite(appState: AppState, groupId: String) async -> String? {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return nil
        }

        let code = IDGenerator.inviteCode()
        let now = Date()
        let expires = Calendar.current.date(byAdding: .day, value: 7, to: now)
            ?? now.addingTimeInterval(7 * 24 * 3600)

        do {
            try await FirestoreService.inviteRef(groupId: groupId, code: code)
                .setData([
                    "groupId": groupId,
                    "createdByUid": user.uid,
                    "expiresAt": Timestamp(date: expires),
                    "maxUses": 10,
                    "uses": 0,
                    "createdAt": Timestamp(date: now),
                    "code": code
                ], merge: true)

            return code

        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }


    // MARK: - Create Group (IMPORTANT: set isDeleted=false)

    func createGroup(appState: AppState, name: String) async -> String? {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return nil
        }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Group name is required."
            return nil
        }

        do {
            let groupId = UUID().uuidString

            let code = IDGenerator.inviteCode()

            // Group doc (note isDeleted: false so filtering works)
            try await FirestoreService.groupRef(groupId).setData([
                "name": trimmed,
                "createdAt": Timestamp(date: Date()),
                "createdByUid": user.uid,
                "isDeleted": false
            ], merge: true)

            // Creator becomes admin member
            try await FirestoreService.membersCol(groupId).document(user.uid).setData([
                "uid": user.uid,
                "email": user.email as Any,
                "name": appState.authUser?.name as Any,
                "role": "admin",
                "joinedAt": Timestamp(date: Date())
            ], merge: true)

            // Create first invite
            try await FirestoreService.inviteRef(groupId: groupId, code: code).setData([
                "groupId": groupId,
                "createdByUid": user.uid,
                "expiresAt": Timestamp(date: Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    ?? Date().addingTimeInterval(7 * 24 * 3600)),
                "maxUses": 10,
                "uses": 0,
                "createdAt": Timestamp(date: Date()),
                "code": code
            ], merge: true)

            await loadGroups(for: user.uid)
            return code

        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }


    // MARK: - Join Group (unchanged)

    func joinGroup(appState: AppState, inviteCode: String) async -> Bool {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return false
        }

        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            errorMessage = "Invite code is required."
            return false
        }

        do {
            let db = FirestoreService.db

            let inviteQuery = try await db.collectionGroup("invites")
                .whereField("code", isEqualTo: code)
                .limit(to: 1)
                .getDocuments()

            guard let inviteDoc = inviteQuery.documents.first else {
                errorMessage = "Invalid invite code."
                return false
            }

            guard let groupRef = inviteDoc.reference.parent.parent else {
                errorMessage = "Invite malformed."
                return false
            }

            let groupId = groupRef.documentID
            let inviteRef = inviteDoc.reference
            let memberRef = FirestoreService.membersCol(groupId).document(user.uid)

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                db.runTransaction({ txn, errPtr -> Any? in

                    let inviteSnap: DocumentSnapshot
                    do {
                        inviteSnap = try txn.getDocument(inviteRef)
                    } catch {
                        errPtr?.pointee = error as NSError
                        return nil
                    }

                    guard let data = inviteSnap.data() else {
                        errPtr?.pointee = NSError(domain: "BillMate", code: 400,
                                                  userInfo: [NSLocalizedDescriptionKey: "Invite not found."])
                        return nil
                    }

                    let expiresAt = Self.dateFromAny(data["expiresAt"]) ?? Date.distantPast
                    let maxUses = data["maxUses"] as? Int ?? 0
                    let uses = data["uses"] as? Int ?? 0

                    if expiresAt < Date() {
                        errPtr?.pointee = NSError(domain: "BillMate", code: 400,
                                                  userInfo: [NSLocalizedDescriptionKey: "Invite expired."])
                        return nil
                    }

                    if uses >= maxUses {
                        errPtr?.pointee = NSError(domain: "BillMate", code: 400,
                                                  userInfo: [NSLocalizedDescriptionKey: "Invite max uses reached."])
                        return nil
                    }

                    txn.updateData(["uses": uses + 1], forDocument: inviteRef)

                    txn.setData([
                        "uid": user.uid,
                        "email": user.email as Any,
                        "name": appState.authUser?.name as Any,
                        "role": "resident",
                        "joinedAt": Timestamp(date: Date())
                    ], forDocument: memberRef, merge: true)

                    return nil

                }, completion: { _, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: ()) }
                })
            }

            await loadGroups(for: user.uid)
            return true

        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }


    // MARK: - Helpers

    private static func dateFromAny(_ value: Any?) -> Date? {
        if let ts = value as? Timestamp { return ts.dateValue() }
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms / 1000.0) }
        if let ms = value as? Int { return Date(timeIntervalSince1970: Double(ms) / 1000.0) }
        return nil
    }
    
    func refreshMyRole(appState: AppState, groupId: String) async {
        guard let user = appState.authUser else { return }

        do {
            let memberSnap = try await FirestoreService
                .membersCol(groupId)
                .document(user.uid)
                .getDocument()

            guard let data = memberSnap.data() else {
                // User is no longer a member
                if appState.activeGroup?.id == groupId {
                    appState.activeGroup = nil
                    appState.activeRole = .resident
                }
                return
            }

            let roleStr = data["role"] as? String ?? "resident"
            let newRole = Role(rawValue: roleStr) ?? .resident

            if appState.activeGroup?.id == groupId {
                appState.activeRole = newRole
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

private extension Error {
    var localizedCaseInsensitiveDescription: String {
        // Keep your UI error messages consistent
        localizedDescription
    }
}
