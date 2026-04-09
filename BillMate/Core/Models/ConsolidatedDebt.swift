//
//  ConsolidatedDebt.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/18/26.
//

import Foundation

struct ConsolidatedDebt: Identifiable, Hashable {
    let id = UUID()
    let fromName: String
    let toName: String
    let amount: Double
}
