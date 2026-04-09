//
//  AddPaymentView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import SwiftUI

struct AddPaymentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var dashboardVM = DashboardViewModel()
    @StateObject private var paymentsVM = PaymentsViewModel()

    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var paidById: String = ""
    @State private var paidToId: String = ""

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if appState.activeRole != .admin {
                    Section {
                        Text("Residents cannot add payments.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Payment") {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    TextField("Note", text: $note)

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Paid By") {
                    if paidByTargets.isEmpty {
                        Text("No available people to pay from.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Person", selection: $paidById) {
                            ForEach(paidByTargets) { target in
                                HStack {
                                    Text(target.name)
                                    if target.isGuest {
                                        Text("Guest")
                                    }
                                }
                                .tag(target.id)
                            }
                        }
                        .onChange(of: paidById) { _, newValue in
                            if paidToId == newValue {
                                paidToId = nextPaidToId(excluding: newValue) ?? ""
                            }
                        }
                    }
                }

                Section("Paid To") {
                    if paidToTargets.isEmpty {
                        Text("No available people to pay to.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Person", selection: $paidToId) {
                            ForEach(paidToTargets) { target in
                                HStack {
                                    Text(target.name)
                                    if target.isGuest {
                                        Text("Guest")
                                    }
                                }
                                .tag(target.id)
                            }
                        }
                        .onChange(of: paidToId) { _, newValue in
                            if paidById == newValue {
                                paidById = nextPaidById(excluding: newValue) ?? ""
                            }
                        }
                    }
                }

                if let error = paymentsVM.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(paymentsVM.isBusy ? "Saving..." : "Add Payment") {
                        Task { await savePayment() }
                    }
                    .disabled(
                        paymentsVM.isBusy ||
                        appState.activeRole != .admin ||
                        paidByTargets.isEmpty ||
                        paidToTargets.isEmpty ||
                        paidById.isEmpty ||
                        paidToId.isEmpty
                    )
                }
            }
            .navigationTitle("Add Payment")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                Task { await loadData() }
            }
        }
    }

    // MARK: - Derived Data

    private var memberTargets: [PaymentTarget] {
        dashboardVM.members.map { member in
            PaymentTarget(
                id: member.uid,
                name: displayName(for: member),
                isGuest: false,
                amountOwed: memberBalance(for: member.uid) ?? 0
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var guestTargets: [PaymentTarget] {
        dashboardVM.balances
            .filter { isGuestBalance($0) }
            .map {
                PaymentTarget(
                    id: $0.id,
                    name: displayGuestName(from: $0),
                    isGuest: true,
                    amountOwed: $0.amountOwed
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Paid By:
    // - all residents
    // - guests only if they owe money
    private var paidByTargets: [PaymentTarget] {
        let guestsWhoOwe = guestTargets.filter { $0.amountOwed > 0.01 }
        return memberTargets + guestsWhoOwe
    }

    // Paid To:
    // - all residents
    // - guests only if money is owed to them
    private var paidToTargets: [PaymentTarget] {
        let guestsWhoAreOwed = guestTargets.filter { $0.amountOwed < -0.01 }
        return memberTargets + guestsWhoAreOwed
    }

    // MARK: - Private

    private func loadData() async {
        guard let homeId = appState.activeHome?.id else { return }

        await dashboardVM.loadAll(homeId: homeId)

        if paidById.isEmpty {
            paidById = paidByTargets.first?.id ?? ""
        }

        if paidToId.isEmpty || paidToId == paidById {
            paidToId = nextPaidToId(excluding: paidById) ?? ""
        }

        if paidById == paidToId {
            paidById = nextPaidById(excluding: paidToId) ?? ""
        }
    }

    private func savePayment() async {
        guard let user = appState.authUser,
              let homeId = appState.activeHome?.id else { return }

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            paymentsVM.errorMessage = "Amount must be a valid number."
            return
        }

        guard amount > 0 else {
            paymentsVM.errorMessage = "Amount must be greater than zero."
            return
        }

        guard !paidById.isEmpty else {
            paymentsVM.errorMessage = "Select who paid."
            return
        }

        guard !paidToId.isEmpty else {
            paymentsVM.errorMessage = "Select who received the payment."
            return
        }

        guard paidById != paidToId else {
            paymentsVM.errorMessage = "Paid By and Paid To cannot be the same."
            return
        }

        let payment = PaymentDoc(
            id: nil,
            amount: amount,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            paidByUid: paidById,
            paidToUid: paidToId,
            createdAt: Date(),
            createdByUid: user.uid,
            updatedAt: nil,
            updatedByUid: nil,
            isDeleted: nil,
            deletedAt: nil,
            deleteExpiresAt: nil,
            deletedByUid: nil,
            deletedByName: nil
        )

        await paymentsVM.addPayment(homeId: homeId, payment: payment)

        if paymentsVM.errorMessage == nil {
            onDone(true)
            dismiss()
        }
    }

    private func nextPaidToId(excluding excludedId: String) -> String? {
        paidToTargets.first(where: { $0.id != excludedId })?.id
    }

    private func nextPaidById(excluding excludedId: String) -> String? {
        paidByTargets.first(where: { $0.id != excludedId })?.id
    }

    private func memberBalance(for uid: String) -> Double? {
        dashboardVM.balances.first(where: { $0.id == uid })?.amountOwed
    }

    private func displayName(for member: MemberDoc) -> String {
        let trimmedName = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        if let email = member.email, !email.isEmpty { return email }
        return member.uid
    }

    private func isGuestBalance(_ balance: MemberBalance) -> Bool {
        balance.id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("guest:")
    }

    private func displayGuestName(from balance: MemberBalance) -> String {
        let trimmed = balance.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().hasPrefix("guest:") {
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }
}

// MARK: - Helpers

private struct PaymentTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let isGuest: Bool
    let amountOwed: Double
}
