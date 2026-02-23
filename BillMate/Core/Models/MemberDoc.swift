import Foundation
import FirebaseFirestore

struct MemberDoc: Codable, Identifiable {
    // Doc ID is the user's uid (same as id)
    @DocumentID var id: String?

    var uid: String
    var email: String?
    let name: String? 
    var role: Role
    var joinedAt: Date
}
