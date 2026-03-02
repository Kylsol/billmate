import Foundation
import FirebaseFirestore

/// Firestore model for homes/{homeId}/events/{eventId}
/// Used for audit logs and activity tracking.
struct EventDoc: Codable, Identifiable {

    // Firestore document ID
    @DocumentID var id: String?

    // What happened
    var type: String              // e.g. "bill_created", "home_deleted", "member_promoted"
    var actorUid: String          // who performed the action
    var actorName: String?        // optional but VERY useful for UI

    // What was affected
    var targetType: String        // "home", "bill", "member"
    var targetId: String          // ID of the affected doc

    // Human-readable message for UI
    var message: String

    // When it happened
    var createdAt: Date
}
