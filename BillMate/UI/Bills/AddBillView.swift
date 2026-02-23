import SwiftUI

struct AddBillView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var dashVM = DashboardViewModel()
    @StateObject private var billsVM = BillsViewModel()

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = Date()

    @State private var paidByUid: String = ""
    @State private var selectedParticipants: Set<String> = []

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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Paid By") {
                    Picker("Member", selection: $paidByUid) {
                        ForEach(dashVM.members, id: \.uid) { m in
                            Text(m.email ?? m.uid).tag(m.uid)
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
                                    if on { selectedParticipants.insert(m.uid) }
                                    else { selectedParticipants.remove(m.uid) }
                                }
                            )) {
                                Text(m.email ?? m.uid)
                            }
                        }
                    }
                    Text("At least 1 participant is required.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let err = billsVM.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }

                Section {
                    Button(billsVM.isBusy ? "Saving..." : "Add Bill") {
                        Task { await addBill() }
                    }
                    .disabled(billsVM.isBusy || appState.activeRole != .admin)
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

    private func loadMembers() async {
        guard let homeId = appState.activeHome?.id else { return }
        await dashVM.loadAll(homeId: homeId)

        // defaults
        if paidByUid.isEmpty, let first = dashVM.members.first?.uid {
            paidByUid = first
        }
        if selectedParticipants.isEmpty {
            selectedParticipants = Set(dashVM.members.map { $0.uid })
        }
    }

    private func addBill() async {
        guard let user = appState.authUser, let homeId = appState.activeHome?.id else { return }
        guard let amount = Double(amountText.replacingOccurrences(of: ",", with: ".")) else {
            billsVM.errorMessage = "Amount must be a number."
            return
        }
        let participants = Array(selectedParticipants)
        if participants.isEmpty {
            billsVM.errorMessage = "Select at least one participant."
            return
        }
        if paidByUid.isEmpty {
            billsVM.errorMessage = "Select who paid."
            return
        }

        let bill = BillDoc(
            id: nil,
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            date: date,
            paidByUid: paidByUid,
            participantUids: participants,
            createdAt: Date(),
            createdByUid: user.uid,
            updatedAt: nil,
            updatedByUid: nil
        )

        await billsVM.addBill(homeId: homeId, bill: bill)
        if billsVM.errorMessage == nil {
            onDone(true)
            dismiss()
        }
    }
}
