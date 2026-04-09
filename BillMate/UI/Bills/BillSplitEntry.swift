//
//  BillSplitEntry.swift
//  BillMate
//
//  Created by Kyle Solomons on 4/6/26.
//

import Foundation

struct BillSplitEntry: Codable, Hashable, Identifiable {
    let id: String

    /// Present when this participant is a real member of the home
    var uid: String?

    /// Always store a display name so guests and removed members can still render correctly
    var name: String

    /// True when this participant is not a member of the home
    var isGuest: Bool

    /// Percent of the bill assigned to this participant, e.g. 33.33
    var percentage: Double?

    /// Optional explicit amount for display / fallback
    var amount: Double?

    init(
        id: String = UUID().uuidString,
        uid: String? = nil,
        name: String,
        isGuest: Bool,
        percentage: Double? = nil,
        amount: Double? = nil
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isGuest = isGuest
        self.percentage = percentage
        self.amount = amount
    }
}
