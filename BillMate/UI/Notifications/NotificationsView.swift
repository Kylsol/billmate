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

    var body: some View {
        NavigationStack {
            List {
                if let err = vm.errorMessage {
                    Text(err).foregroundStyle(.red)
                }

                if vm.events.isEmpty {
                    Text("No events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(vm.events) { e in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(e.message)
                                .font(.headline)

                            HStack {
                                Text(e.type)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(e.createdAt, style: .relative)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Activity")
            .onAppear {
                Task {
                    guard let homeId = appState.activeHome?.id else { return }
                    await vm.load(homeId: homeId)
                }
            }
        }
    }
}
