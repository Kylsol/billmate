//
//  BillDoc.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Foundation
import FirebaseFirestore

/// Firestore model for homes/{homeId}/bills/{billId}
struct BillDoc: Codable, Identifiable {

    @DocumentID var id: String?

    // Core bill fields
    var description: String
    var amount: Double
    var date: Date
    var category: String?

    var paidByUid: String

    /// Legacy equal-split support
    var participantUids: [String]

    /// New split system
    /// "equal" or "custom"
    var splitMode: String?

    /// Participants for equal/custom split, including guests
    var splitEntries: [BillSplitEntry]?

    var createdAt: Date
    var createdByUid: String

    // Optional update tracking
    var updatedAt: Date?
    var updatedByUid: String?

    // Soft delete / recycle bin fields
    var isDeleted: Bool?
    var deletedAt: Date?
    var deleteExpiresAt: Date?
    var deletedByUid: String?
    var deletedByName: String?
}
