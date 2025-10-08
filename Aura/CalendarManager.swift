// CalendarManager.swift

import Foundation
import EventKit

// **FIXED**: Added the endDate property
struct Meeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date? // Can be nil for events without a set end time
}

@MainActor
class CalendarManager: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var permissionGranted = false

    private let eventStore = EKEventStore()

    init() {
        checkPermissionStatus()
    }

    private func checkPermissionStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized {
            self.permissionGranted = true
            fetchTodaysMeetings()
        }
    }

    func requestAccess() async {
        do {
            let granted = try await eventStore.requestAccess(to: .event)
            self.permissionGranted = granted
            if granted {
                fetchTodaysMeetings()
            }
        } catch {
            print("Error requesting calendar access: \(error)")
            self.permissionGranted = false
        }
    }

    func fetchTodaysMeetings() {
        let calendar = Calendar.current
        let today = Date()
        guard let startOfToday = calendar.startOfDay(for: today) as Date?,
              let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) as Date? else {
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: nil)
        let events = eventStore.events(matching: predicate)

        // **FIXED**: Map the EKEvent objects including the endDate
        self.meetings = events.map { event in
            Meeting(id: event.eventIdentifier, title: event.title, startDate: event.startDate, endDate: event.endDate)
        }
        
        print("Found \(self.meetings.count) meetings for today.")
    }
}
