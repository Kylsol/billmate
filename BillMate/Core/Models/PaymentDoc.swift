import Foundation
import FirebaseFirestore

/// Firestore model for homes/{homeId}/payments/{paymentId}
struct PaymentDoc: Codable, Identifiable {

    // Firestore document ID
    @DocumentID var id: String?

    // Core payment info
    var amount: Double
    var date: Date
    var note: String

    // Who paid and who received
    var paidByUid: String
    var paidToUid: String?

    // Audit fields
    var createdAt: Date
    var createdByUid: String

    var updatedAt: Date?
    var updatedByUid: String?
}
