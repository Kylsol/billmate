import Foundation
import FirebaseFirestore

struct PaymentDoc: Codable, Identifiable {
    @DocumentID var id: String?

    var amount: Double
    var date: Date
    var note: String

    var paidByUid: String
    var paidToUid: String?
    
    var createdAt: Date
    var createdByUid: String

    var updatedAt: Date?
    var updatedByUid: String?
}
