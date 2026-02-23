import Foundation
import FirebaseFirestore

struct EventDoc: Codable, Identifiable {
    @DocumentID var id: String?

    var type: String
    var actorUid: String

    var targetType: String
    var targetId: String

    var message: String
    var createdAt: Date
}
