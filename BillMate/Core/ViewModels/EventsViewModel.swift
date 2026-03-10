//
//  EventsViewModel.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [EventDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private var billsById: [String: BillDoc] = [:]
    private var paymentsById: [String: PaymentDoc] = [:]
    private var membersByUid: [String: MemberDoc] = [:]

    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            async let eventsTask = FirestoreService.eventsCol(homeId)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()

            async let billsTask = FirestoreService.billsCol(homeId)
                .getDocuments()

            async let paymentsTask = FirestoreService.paymentsCol(homeId)
                .getDocuments()

            async let membersTask = FirestoreService.membersCol(homeId)
                .getDocuments()

            let (eventsSnap, billsSnap, paymentsSnap, membersSnap) = try await (
                eventsTask,
                billsTask,
                paymentsTask,
                membersTask
            )

            self.events = try eventsSnap.documents.map { try $0.data(as: EventDoc.self) }

            let bills = try billsSnap.documents.map { try $0.data(as: BillDoc.self) }
            self.billsById = Dictionary(
                uniqueKeysWithValues: bills.compactMap { bill in
                    guard let id = bill.id else { return nil }
                    return (id, bill)
                }
            )

            let payments = try paymentsSnap.documents.map { try $0.data(as: PaymentDoc.self) }
            self.paymentsById = Dictionary(
                uniqueKeysWithValues: payments.compactMap { payment in
                    guard let id = payment.id else { return nil }
                    return (id, payment)
                }
            )

            let members = try membersSnap.documents.map { try $0.data(as: MemberDoc.self) }
            self.membersByUid = Dictionary(uniqueKeysWithValues: members.map { ($0.uid, $0) })

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filters

    func isBillEvent(_ event: EventDoc) -> Bool {
        event.targetType == "bill" && !event.type.contains("updated") && !event.type.contains("deleted")
    }

    func isPaymentEvent(_ event: EventDoc) -> Bool {
        event.targetType == "payment" && !event.type.contains("updated") && !event.type.contains("deleted")
    }

    func isUpdateEvent(_ event: EventDoc) -> Bool {
        event.type.contains("updated") || event.type.contains("deleted")
    }

    // MARK: - Navigation Support

    func hasDestination(for event: EventDoc) -> Bool {
        if event.type.contains("deleted") {
            return false
        }

        switch event.targetType {
        case "bill":
            return billsById[event.targetId] != nil
        case "payment":
            return paymentsById[event.targetId] != nil
        default:
            return false
        }
    }

    func bill(for event: EventDoc) -> BillDoc? {
        billsById[event.targetId]
    }

    func payment(for event: EventDoc) -> PaymentDoc? {
        paymentsById[event.targetId]
    }

    // MARK: - Display Text

    func titleText(for event: EventDoc) -> String {
        let actor = normalizedActorName(event.actorName, uid: event.actorUid)

        if event.type.contains("deleted") {
            switch event.targetType {
            case "bill":
                if let bill = billsById[event.targetId] {
                    let category = normalizedCategory(bill.category)
                    return "Update: \(actor) Deleted Bill (\(category))"
                }
                return "Update: \(actor) Deleted Bill"

            case "payment":
                return "Update: \(actor) Deleted Payment"

            default:
                return "Update: \(actor) Deleted Item"
            }
        }

        if event.type.contains("updated") {
            switch event.targetType {
            case "bill":
                if let bill = billsById[event.targetId] {
                    let category = normalizedCategory(bill.category)
                    return "Updated: Bill for \(category)"
                }
                return "Updated: Bill"

            case "payment":
                if let payment = paymentsById[event.targetId] {
                    let payer = displayName(for: payment.paidByUid)
                    let receiver = displayName(for: payment.paidToUid ?? "")
                    return "Updated: Payment to \(receiver) from \(payer)"
                }
                return "Updated: Payment"

            default:
                let target = capitalizedTargetType(event.targetType)
                return "\(actor) updated \(target)"
            }
        }

        switch event.targetType {
        case "bill":
            if let bill = billsById[event.targetId] {
                let category = normalizedCategory(bill.category)
                return "Bill: \(category) - \(currencyString(bill.amount))"
            }
            return "Bill"

        case "payment":
            if let payment = paymentsById[event.targetId] {
                let payer = displayName(for: payment.paidByUid)
                let receiver = displayName(for: payment.paidToUid ?? "")
                return "Payment: \(payer) paid \(receiver) \(currencyString(payment.amount))"
            }
            return "Payment"

        default:
            return event.message
        }
    }

    func subtitleText(for event: EventDoc) -> String {
        if event.type.contains("deleted") {
            let actor = normalizedActorName(event.actorName, uid: event.actorUid)

            switch event.targetType {
            case "bill":
                if let bill = billsById[event.targetId] {
                    let category = normalizedCategory(bill.category)
                    return "\(actor) deleted Bill (\(category))"
                }
                return "\(actor) deleted Bill"

            case "payment":
                return "\(actor) deleted Payment"

            default:
                return "\(actor) deleted item"
            }
        }

        if event.type.contains("updated") {
            let actor = normalizedActorName(event.actorName, uid: event.actorUid)

            if let field = event.changedField,
               let oldValue = event.oldValue,
               let newValue = event.newValue {
                let extraSuffix: String
                if let changeCount = event.changeCount, changeCount > 1 {
                    extraSuffix = " + more"
                } else {
                    extraSuffix = ""
                }

                return "\(actor) updated \(field): \(oldValue) to \(newValue)\(extraSuffix)"
            }

            return "\(actor) updated this item"
        }

        switch event.targetType {
        case "bill":
            if let bill = billsById[event.targetId] {
                return "Paid by: \(displayName(for: bill.paidByUid))"
            }
            return event.type

        case "payment":
            if let payment = paymentsById[event.targetId] {
                let trimmedNote = payment.note.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedNote.isEmpty ? "No note" : trimmedNote
            }
            return event.type

        default:
            return event.type
        }
    }

    // MARK: - Helpers

    func displayDate(for event: EventDoc) -> String {

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        switch event.targetType {

        case "bill":
            if let bill = billsById[event.targetId] {
                return formatter.string(from: bill.date)
            }

        case "payment":
            if let payment = paymentsById[event.targetId] {
                return formatter.string(from: payment.date)
            }

        default:
            break
        }

        return formatter.string(from: event.createdAt)
    }
    
    
    private func displayName(for uid: String) -> String {
        guard !uid.isEmpty else { return "Unknown" }

        if let member = membersByUid[uid] {
            let trimmedName = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }
            if let email = member.email, !email.isEmpty { return email }
        }
        return uid
    }

    private func normalizedActorName(_ actorName: String?, uid: String) -> String {
        let trimmed = actorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return displayName(for: uid)
    }

    private func normalizedCategory(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
    }

    private func capitalizedTargetType(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Item" }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
    }

    private func currencyString(_ amount: Double) -> String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return amount.formatted(.currency(code: code))
    }

    private func changeText(for event: EventDoc) -> String {
        switch event.targetType {
        case "bill":
            if let bill = billsById[event.targetId] {
                return "Now \(normalizedCategory(bill.category)) - \(currencyString(bill.amount))"
            }
            return "Changes saved"

        case "payment":
            if let payment = paymentsById[event.targetId] {
                let payer = displayName(for: payment.paidByUid)
                let receiver = displayName(for: payment.paidToUid ?? "")
                return "Now \(payer) → \(receiver) \(currencyString(payment.amount))"
            }
            return "Changes saved"

        default:
            return "Changes saved"
        }
    }
}
