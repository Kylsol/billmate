//  EventDoc.swift
//  BillMate
//
//  Firestore model for homes/{homeId}/events/{eventId}
//  Used for audit logs and activity tracking.

import Foundation
import FirebaseFirestore

struct EventDoc: Codable, Identifiable {

    // MARK: - Firestore Document ID

    @DocumentID var id: String?

    // MARK: - Action Metadata

    /// What happened (examples: "bill_created", "bill_deleted", "payment_deleted", "home_deleted")
    var type: String

    /// UID of the user who performed the action
    var actorUid: String

    /// Display name of the user who performed the action (helps the UI avoid lookups)
    /// Optional so older event docs decode safely.
    var actorName: String?

    // MARK: - Target Metadata

    /// What was affected (examples: "home", "bill", "payment", "member")
    var targetType: String

    /// Document ID of the affected target
    var targetId: String

    // MARK: - UI Message

    /// Human-readable message for your feed UI
    var message: String

    // MARK: - Timestamp

    /// When the event occurred
    var createdAt: Date
}
