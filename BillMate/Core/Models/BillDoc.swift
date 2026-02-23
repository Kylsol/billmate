import Foundation
import FirebaseFirestore

struct BillDoc: Codable, Identifiable {
    @DocumentID var id: String?

    var description: String
    var amount: Double
    var date: Date

    var paidByUid: String
    var participantUids: [String]

    var createdAt: Date
    var createdByUid: String

    var updatedAt: Date?
    var updatedByUid: String?
}
