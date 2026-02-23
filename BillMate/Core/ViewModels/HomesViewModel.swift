import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class HomesViewModel: ObservableObject {

    @Published var homes: [HomeDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    // MARK: - Load Homes

    func loadHomes(for uid: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let db = FirestoreService.db

            let snap = try await db.collectionGroup("members")
                .whereField("uid", isEqualTo: uid)
                .getDocuments()

            var loaded: [HomeDoc] = []

            for doc in snap.documents {
                guard let homeRef = doc.reference.parent.parent else { continue }

                let homeSnap = try await homeRef.getDocument()
                guard let data = homeSnap.data() else { continue }

                let home = HomeDoc(
                    id: homeRef.documentID,
                    name: data["name"] as? String ?? "Home",
                    createdAt: Self.dateFromAny(data["createdAt"]) ?? Date(),
                    createdByUid: data["createdByUid"] as? String ?? ""
                )

                loaded.append(home)
            }

            homes = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Select Home

    func selectHome(appState: AppState, uid: String, homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let homeSnap = try await FirestoreService.homeRef(homeId).getDocument()
            guard let homeData = homeSnap.data() else {
                throw NSError(domain: "BillMate", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Home not found."])
            }

            let memberSnap = try await FirestoreService
                .membersCol(homeId)
                .document(uid)
                .getDocument()

            guard let memberData = memberSnap.data() else {
                throw NSError(domain: "BillMate", code: 404,
                              userInfo: [NSLocalizedDescriptionKey: "Membership not found."])
            }

            let home = HomeDoc(
                id: homeId,
                name: homeData["name"] as? String ?? "Home",
                createdAt: Self.dateFromAny(homeData["createdAt"]) ?? Date(),
                createdByUid: homeData["createdByUid"] as? String ?? ""
            )

            let roleStr = memberData["role"] as? String ?? "resident"

            appState.activeHome = home
            appState.activeRole = Role(rawValue: roleStr) ?? .resident

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Create Invite

    /// Creates a new invite code for an existing home.
    /// Used by DashboardView's "Create Invite Code" action.
    func createInvite(homeId: String) async throws -> String {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        // Generate a new code and invite doc
        let code = IDGenerator.inviteCode()

        let invite = InviteDoc(
            id: code,
            homeId: homeId,
            createdByUid: "", // optional; if you want this, pass uid into this method and set it
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())
                ?? Date().addingTimeInterval(7 * 24 * 3600),
            maxUses: 10,
            uses: 0,
            createdAt: Date(),
            code: code
        )

        do {
            try await FirestoreService.setEncodable(
                invite,
                to: FirestoreService.inviteRef(homeId: homeId, code: code)
            )
            return code
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Create Home

    func createHome(appState: AppState, name: String) async -> String? {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        guard let user = appState.authUser else {
            errorMessage = "Not signed in."
            return nil
        }
        
        print("AppState authUser uid:", user.uid)
        print("FirebaseAuth currentUser uid:", Auth.auth().currentUser?.uid as Any)

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Home name is required."
            return nil
        }

        do {
            let homeId = UUID().uuidString

            let home = HomeDoc(
                id: homeId,
                name: trimmed,
                createdAt: Date(),
                createdByUid: user.uid
            )

            let member = MemberDoc(
                id: user.uid,
                uid: user.uid,
                email: user.email,
                name: user.name,
                role: .admin,
                joinedAt: Date()
            )

            let code = IDGenerator.inviteCode()

            let invite = InviteDoc(
                id: code,
                homeId: homeId,
                createdByUid: user.uid,
                expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    ?? Date().addingTimeInterval(7 * 24 * 3600),
                maxUses: 10,
                uses: 0,
                createdAt: Date(),
                code: code
            )

//            print("WRITE 1: homes/\(homeId)")
//            try await FirestoreService.setEncodable(
//                home,
//                to: FirestoreService.homeRef(homeId)
//            )
//
//            print("WRITE 2: homes/\(homeId)/members/\(user.uid)")
//            try await FirestoreService.setEncodable(
//                member,
//                to: FirestoreService.membersCol(homeId).document(user.uid)
//            )
//
//            print("WRITE 3: homes/\(homeId)/invites/\(code)")
//            try await FirestoreService.setEncodable(
//                invite,
//                to: FirestoreService.inviteRef(homeId: homeId, code: code)
//            )
            
            print("HOME PATH:", FirestoreService.homeRef(homeId).path)
            print("MEMBER PATH:", FirestoreService.membersCol(homeId).document(user.uid).path)
            print("INVITE PATH:", FirestoreService.inviteRef(homeId: homeId, code: code).path)
            
            print("WRITE 1: homes/\(homeId)")
            try await FirestoreService.homeRef(homeId).setData([
                "name": trimmed,
                "createdAt": Timestamp(date: Date()),
                "createdByUid": user.uid
            ])

            print("WRITE 2: homes/\(homeId)/members/\(user.uid)")
            try await FirestoreService.membersCol(homeId).document(user.uid).setData([
                "uid": user.uid,
                "email": user.email as Any,
                "name": appState.authUser?.name as Any,   // ✅ ADD THIS
                "role": "admin",
                "joinedAt": Timestamp(date: Date())
            ], merge: true)

            print("WRITE 3: homes/\(homeId)/invites/\(code)")
            try await FirestoreService.inviteRef(homeId: homeId, code: code).setData([
                "homeId": homeId,
                "createdByUid": user.uid,
                "expiresAt": Timestamp(date: Calendar.current.date(byAdding: .day, value: 7, to: Date())
                    ?? Date().addingTimeInterval(7 * 24 * 3600)),
                "maxUses": 10,
                "uses": 0,
                "createdAt": Timestamp(date: Date()),
                "code": code
            ])

            await loadHomes(for: user.uid)
            return code

        } catch {
            print("CreateHome error:", error)
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Join Home

    func joinHome(appState: AppState, inviteCode: String) async -> Bool {
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

            guard let homeRef = inviteDoc.reference.parent.parent else {
                errorMessage = "Invite malformed."
                return false
            }

            let homeId = homeRef.documentID
            let inviteRef = inviteDoc.reference
            let memberRef = FirestoreService.membersCol(homeId).document(user.uid)

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
                        "name": appState.authUser?.name as Any,   // ✅ ADD THIS
                        "role": "resident",
                        "joinedAt": Timestamp(date: Date())
                    ], forDocument: memberRef, merge: true)

                    return nil

                }, completion: { _, error in
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: ()) }
                })
            }

            await loadHomes(for: user.uid)
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
}
