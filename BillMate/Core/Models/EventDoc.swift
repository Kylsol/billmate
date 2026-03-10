//  EventDoc.swift
//  BillMate
//
//  Firestore model for homes/{homeId}/events/{eventId}
//  Used for audit logs and activity tracking.

import Foundation
import FirebaseFirestore

struct EventDoc: Codable, Identifiable {

    @DocumentID var id: String?

    // MARK: - Action Metadata

    var type: String
    var actorUid: String
    var actorName: String?

    // MARK: - Target Metadata

    var targetType: String
    var targetId: String

    // MARK: - UI Message

    var message: String

    // MARK: - Update Detail Metadata

    /// Example: "Category", "Amount", "Note", "Paid By", "Paid To", "Date"
    var changedField: String?

    /// Human-readable old value for the feed UI
    var oldValue: String?

    /// Human-readable new value for the feed UI
    var newValue: String?
    
    var changeCount: Int?

    // MARK: - Timestamp

    var createdAt: Date
}
