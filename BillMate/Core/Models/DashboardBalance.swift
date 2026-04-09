//
//  DashboardBalance.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/18/26.
//

import Foundation

struct DashboardBalance: Identifiable, Hashable {
    let id = UUID()
    let displayName: String
    let amountOwed: Double
}
