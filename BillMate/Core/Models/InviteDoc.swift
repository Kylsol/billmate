import Foundation

struct InviteDoc: Identifiable, Codable {
    var id: String?
    var homeId: String
    var createdByUid: String
    var expiresAt: Date
    var maxUses: Int
    var uses: Int
    var createdAt: Date

    // required so we can query invites by field (collectionGroup query)
    var code: String
}
