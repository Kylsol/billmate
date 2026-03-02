import Foundation
import FirebaseFirestore

/// Firestore model for homes/{homeId}/bills/{billId}
struct BillDoc: Codable, Identifiable {

    // Firestore document id
    @DocumentID var id: String?

    // Core bill fields
    var description: String
    var amount: Double
    var date: Date

    var paidByUid: String
    var participantUids: [String]

    var createdAt: Date
    var createdByUid: String

    // Optional update tracking
    var updatedAt: Date?
    var updatedByUid: String?

    // Soft delete / recycle bin fields
    // Optional so older docs decode safely
    var isDeleted: Bool?
    var deletedAt: Date?
    var deleteExpiresAt: Date?
    var deletedByUid: String?
    var deletedByName: String?
}
