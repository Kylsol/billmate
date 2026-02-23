import Combine
import Foundation
import FirebaseFirestore

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [EventDoc] = []
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    func load(homeId: String) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let snap = try await FirestoreService.eventsCol(homeId)
                .order(by: "createdAt", descending: true)
                .limit(to: 100)
                .getDocuments()
            self.events = try snap.documents.map { try $0.data(as: EventDoc.self) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
