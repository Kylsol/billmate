import Foundation
import FirebaseFirestore

/// Role a member can have inside a home.
enum MemberRole: String, Codable, CaseIterable {
    case admin
    case resident
}

/// Firestore model for homes/{homeId}/members/{uid}
struct MemberDoc: Codable, Identifiable {

    // Firestore document ID (typically the user's uid)
    @DocumentID var id: String?

    // Core identity fields
    var uid: String
    var email: String?
    var name: String?

    // Authorization role inside the home
    var role: MemberRole

    // When the user joined this home
    var joinedAt: Date
}
