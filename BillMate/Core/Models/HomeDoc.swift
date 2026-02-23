import Foundation
import FirebaseFirestore

struct HomeDoc: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var createdAt: Date
    var createdByUid: String
}
