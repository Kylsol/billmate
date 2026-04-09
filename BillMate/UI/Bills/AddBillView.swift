//
//  AddBillView.swift
//  BillMate
//
//  Created by Kyle Solomons on 3/1/26.
//

import SwiftUI

struct AddBillView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var dashVM = DashboardViewModel()
    @StateObject private var billsVM = BillsViewModel()

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var category: String = BillCategory.allCases.first?.rawValue ?? "Other"

    @State private var paidByUid: String = ""
    @State private var selectedParticipants: Set<String> = []

    @State private var guestRows: [GuestInputRow] = [GuestInputRow()]
    @State private var useCustomSplit: Bool = false

    /// Keyed by participant id (member uid or guest row id)
    @State private var customPercentages: [String: Double] = [:]

    let onDone: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if appState.activeRole != .admin {
                    Section {
                        Text("Residents can’t add bills.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Bill") {
                    TextField("Description", text: $descriptionText)

                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    Picker("Category", selection: $category) {
                        ForEach(BillCategory.allCases, id: \.rawValue) { item in
                            Text(item.rawValue).tag(item.rawValue)
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Paid By") {
                    Picker("Member", selection: $paidByUid) {
                        ForEach(dashVM.members, id: \.uid) { m in
                            Text(displayName(for: m))
                                .tag(m.uid)
                        }
                    }
                }

                Section("Split With") {
                    if dashVM.members.isEmpty {
                        Text("No members found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(dashVM.members, id: \.uid) { m in
                            Toggle(isOn: Binding(
                                get: { selectedParticipants.contains(m.uid) },
                                set: { on in
                                    if on {
                                        selectedParticipants.insert(m.uid)
                                    } else {
                                        selectedParticipants.remove(m.uid)
                                        customPercentages[m.uid] = nil
                                    }

                                    if useCustomSplit {
                                        seedEqualPercentagesIfNeeded()
                                    }
                                }
                            )) {
                                Text(displayName(for: m))
                            }
                        }
                    }

                    ForEach($guestRows) { $guest in
                        TextField("Guest name", text: $guest.name)
                            .onChange(of: guest.name) { _, _ in
                                normalizeGuestRows()
                                if useCustomSplit {
                                    seedEqualPercentagesIfNeeded()
                                }
                            }
                    }

                    Toggle("Custom Split", isOn: $useCustomSplit)
                        .onChange(of: useCustomSplit) { _, newValue in
                            if newValue {
                                seedEqualPercentagesIfNeeded()
                            } else {
                                customPercentages.removeAll()
                            }
                        }

                    Text("At least 1 participant is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if useCustomSplit {
                    Section("Custom Split") {
                        let participants = allParticipants()

                        if participants.isEmpty {
                            Text("Add at least one member or guest to create a custom split.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(participants) { p in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(p.name)
                                            .font(.headline)

                                        Spacer()

                                        TextField(
                                            "0.00",
                                            value: Binding(
                                                get: {
                                                    calculatedAmount(
                                                        totalAmount: parsedAmount,
                                                        percentage: customPercentages[p.id] ?? 0
                                                    )
                                                },
                                                set: { newAmount in
                                                    updateAmount(newAmount, for: p.id)
                                                }
                                            ),
                                            format: .currency(code: currencyCode())
                                        )
                                        .multilineTextAlignment(.trailing)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 120)
                                    }

                                    HStack(spacing: 8) {
                                        TextField(
                                            "0",
                                            value: Binding(
                                                get: { customPercentages[p.id] ?? 0 },
                                                set: { newPercentage in
                                                    updatePercentage(newPercentage, for: p.id)
                                                }
                                            ),
                                            format: .number
                                        )
                                        .keyboardType(.decimalPad)
                                        .frame(width: 70)

                                        Text("%")
                                            .foregroundStyle(.secondary)

                                        Spacer()
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            let total = customPercentageTotal
                            let deltaPercent = total - 100
                            let deltaAmount = parsedAmount * (abs(deltaPercent) / 100.0)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Total")
                                        .fontWeight(.semibold)

                                    Spacer()

                                    Text("\(total, specifier: "%.2f")%")
                                        .monospacedDigit()
                                        .foregroundStyle(
                                            abs(total - 100) < 0.01 ? .green : .red
                                        )
                                }

                                if abs(deltaPercent) >= 0.01 {
                                    HStack {
                                        Text(deltaPercent > 0 ? "Over by" : "Under by")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)

                                        Spacer()

                                        Text(deltaAmount, format: .currency(code: currencyCode()))
                                            .font(.footnote.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(deltaPercent > 0 ? .red : .orange)
                                    }
                                }

                                if total > 100 {
                                    Text("Custom split is over 100%. Reduce one or more values before saving.")
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                } else if total < 100 {
                                    Text("Custom split must total 100%.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Custom split totals 100%.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let err = billsVM.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(billsVM.isBusy ? "Saving..." : "Add Bill") {
                        Task { await addBill() }
                    }
                    .disabled(!canSaveBill)
                }
            }
            .navigationTitle("Add Bill")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                Task { await loadMembers() }
            }
        }
    }

    private var canSaveBill: Bool {
        guard appState.activeRole == .admin, !billsVM.isBusy else { return false }

        if useCustomSplit {
            return abs(customPercentageTotal - 100) < 0.01
        }

        return true
    }

    private var parsedAmount: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var customPercentageTotal: Double {
        allParticipants()
            .reduce(0) { partial, participant in
                partial + (customPercentages[participant.id] ?? 0)
            }
    }

    private func loadMembers() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)

        if paidByUid.isEmpty, let first = dashVM.members.first?.uid {
            paidByUid = first
        }

        if selectedParticipants.isEmpty {
            selectedParticipants = Set(dashVM.members.map { $0.uid })
        }

        normalizeGuestRows()

        if useCustomSplit {
            seedEqualPercentagesIfNeeded()
        }
    }

    private func addBill() async {
        guard let user = appState.authUser,
              let homeId = appState.activeHome?.id else { return }

        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            billsVM.errorMessage = "Amount must be a number."
            return
        }

        guard amount > 0 else {
            billsVM.errorMessage = "Amount must be greater than zero."
            return
        }

        let participants = allParticipants()
        if participants.isEmpty {
            billsVM.errorMessage = "Select at least one participant or guest."
            return
        }

        if paidByUid.isEmpty {
            billsVM.errorMessage = "Select who paid."
            return
        }

        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDescription.isEmpty {
            billsVM.errorMessage = "Description is required."
            return
        }

        let splitEntries: [BillSplitEntry]

        if useCustomSplit {
            let total = customPercentageTotal

            guard abs(total - 100) < 0.01 else {
                billsVM.errorMessage = "Custom split must total 100%."
                return
            }

            splitEntries = participants.map { participant in
                let percentage = customPercentages[participant.id] ?? 0
                let amountForParticipant = calculatedAmount(
                    totalAmount: amount,
                    percentage: percentage
                )

                return BillSplitEntry(
                    id: participant.id,
                    uid: participant.uid,
                    name: participant.name,
                    isGuest: participant.isGuest,
                    percentage: percentage,
                    amount: amountForParticipant
                )
            }
        } else {
            let equalPercentage = 100.0 / Double(participants.count)

            splitEntries = participants.map { participant in
                let amountForParticipant = calculatedAmount(
                    totalAmount: amount,
                    percentage: equalPercentage
                )

                return BillSplitEntry(
                    id: participant.id,
                    uid: participant.uid,
                    name: participant.name,
                    isGuest: participant.isGuest,
                    percentage: equalPercentage,
                    amount: amountForParticipant
                )
            }
        }

        let bill = BillDoc(
            id: nil,
            description: trimmedDescription,
            amount: amount,
            date: date,
            category: category,
            paidByUid: paidByUid,
            participantUids: participants.compactMap { $0.uid },
            splitMode: useCustomSplit ? "custom" : "equal",
            splitEntries: splitEntries,
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

        await billsVM.addBill(homeId: homeId, bill: bill)
        if billsVM.errorMessage == nil {
            onDone(true)
            dismiss()
        }
    }

    private func allParticipants() -> [TempParticipant] {
        let members = dashVM.members
            .filter { selectedParticipants.contains($0.uid) }
            .map {
                TempParticipant(
                    id: $0.uid,
                    uid: $0.uid,
                    name: displayName(for: $0),
                    isGuest: false
                )
            }

        let guests = guestRows
            .map {
                TempParticipant(
                    id: $0.id,
                    uid: nil,
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    isGuest: true
                )
            }
            .filter { !$0.name.isEmpty }

        return members + guests
    }

    private func normalizeGuestRows() {
        let trimmed = guestRows.map {
            GuestInputRow(id: $0.id, name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let nonEmpty = trimmed.filter { !$0.name.isEmpty }
        guestRows = nonEmpty + [GuestInputRow()]
    }

    private func seedEqualPercentagesIfNeeded() {
        let participants = allParticipants()
        guard !participants.isEmpty else { return }

        let existingIds = Set(customPercentages.keys)
        let participantIds = Set(participants.map(\.id))

        customPercentages = customPercentages.filter { participantIds.contains($0.key) }

        if existingIds != participantIds || customPercentages.isEmpty {
            let equalPercentage = 100.0 / Double(participants.count)
            var newValues: [String: Double] = [:]

            for participant in participants {
                newValues[participant.id] = equalPercentage
            }

            customPercentages = newValues
        }
    }

    private func calculatedAmount(totalAmount: Double, percentage: Double) -> Double {
        totalAmount * (percentage / 100.0)
    }

    private func updatePercentage(_ newPercentage: Double, for participantId: String) {
        let clamped = max(0, newPercentage)
        customPercentages[participantId] = clamped
    }

    private func updateAmount(_ newAmount: Double, for participantId: String) {
        let total = parsedAmount

        guard total > 0 else {
            customPercentages[participantId] = 0
            return
        }

        let clampedAmount = max(0, newAmount)
        let percentage = (clampedAmount / total) * 100.0
        customPercentages[participantId] = percentage
    }

    private func displayName(for member: MemberDoc) -> String {
        let trimmedName = (member.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        if let email = member.email, !email.isEmpty { return email }
        return member.uid
    }

    private func currencyCode() -> String {
        Locale.current.currency?.identifier ?? "USD"
    }
}

// MARK: - Helpers

private struct TempParticipant: Identifiable {
    let id: String
    let uid: String?
    let name: String
    let isGuest: Bool
}

private struct GuestInputRow: Identifiable {
    let id: String
    var name: String

    init(id: String = UUID().uuidString, name: String = "") {
        self.id = id
        self.name = name
    }
}

// MARK: - Categories

private enum BillCategory: String, CaseIterable {
    case food = "Food"
    case transport = "Transport"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case rent = "Rent"
    case groceries = "Groceries"
    case diningOut = "Dining Out"
    case household = "Household"
    case internet = "Internet"
    case phone = "Phone"
    case subscriptions = "Subscriptions"
    case health = "Health"
    case education = "Education"
    case travel = "Travel"
    case other = "Other"
}
