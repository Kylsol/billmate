//
//  NotificationsView.swift
//  BillMate
//
//  Created by Kyle Solomons on 2/23/26.
//

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = EventsViewModel()

    @State private var filter: ActivityFilter = .all

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(ActivityFilter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let err = vm.errorMessage {
                Text(err)
                    .foregroundStyle(.red)
            }

            if filteredEvents.isEmpty {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredEvents) { event in
                    NavigationLink {
                        destinationView(for: event)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vm.titleText(for: event))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(vm.subtitleText(for: event))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(vm.displayDate(for: event))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!vm.hasDestination(for: event))
                }
            }
        }
        .navigationTitle("Activity")
        .task {
            guard let homeId = appState.activeHome?.id else { return }
            await vm.load(homeId: homeId)
        }
    }

    private var filteredEvents: [EventDoc] {
        switch filter {
        case .all:
            return vm.events
        case .bills:
            return vm.events.filter { vm.isBillEvent($0) }
        case .payments:
            return vm.events.filter { vm.isPaymentEvent($0) }
        case .updates:
            return vm.events.filter { vm.isUpdateEvent($0) }
        }
    }

    private var emptyStateText: String {
        switch filter {
        case .all:
            return "No activity yet."
        case .bills:
            return "No bill activity yet."
        case .payments:
            return "No payment activity yet."
        case .updates:
            return "No updates yet."
        }
    }

    @ViewBuilder
    private func destinationView(for event: EventDoc) -> some View {
        switch event.targetType {
        case "bill":
            if let bill = vm.bill(for: event) {
                BillDetailView(
                    bill: bill,
                    isRecycleBinItem: false,
                    onChanged: {
                        Task {
                            guard let homeId = appState.activeHome?.id else { return }
                            await vm.load(homeId: homeId)
                        }
                    }
                )
            } else {
                Text("Bill not found.")
                    .foregroundStyle(.secondary)
            }

        case "payment":
            if let payment = vm.payment(for: event) {
                PaymentDetailView(
                    payment: payment,
                    isRecycleBinItem: false,
                    onChanged: {
                        Task {
                            guard let homeId = appState.activeHome?.id else { return }
                            await vm.load(homeId: homeId)
                        }
                    }
                )
            } else {
                Text("Payment not found.")
                    .foregroundStyle(.secondary)
            }

        default:
            Text("No detail available.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Filter

private enum ActivityFilter: String, CaseIterable {
    case all = "All"
    case bills = "Bills"
    case payments = "Payments"
    case updates = "Updates"
}
