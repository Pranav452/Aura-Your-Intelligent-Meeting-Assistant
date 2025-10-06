// CalendarManager.swift

import Foundation
import EventKit

// This struct will represent a single meeting in our app.
// It's Identifiable so we can use it in a SwiftUI List.
struct Meeting: Identifiable {
    let id: String
    let title: String
    let startDate: Date
}

@MainActor
class CalendarManager: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var permissionGranted = false

    private let eventStore = EKEventStore()

    init() {
        // When the app starts, check if we already have permission.
        checkPermissionStatus()
    }

    private func checkPermissionStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .authorized {
            print("Calendar permission was already granted.")
            self.permissionGranted = true
            // If we have permission, fetch meetings immediately.
            fetchTodaysMeetings()
        } else {
            print("Calendar permission has not been granted yet.")
        }
    }

    func requestAccess() async {
        do {
            print("Requesting calendar access...")
            let granted = try await eventStore.requestAccess(to: .event)
            self.permissionGranted = granted
            if granted {
                print("Calendar access granted by user.")
                // If permission is given, fetch meetings.
                fetchTodaysMeetings()
            } else {
                print("Calendar access denied by user.")
            }
        } catch {
            print("Error requesting calendar access: \(error)")
            self.permissionGranted = false
        }
    }

    func fetchTodaysMeetings() {
        print("--- Starting to fetch today's meetings ---")
        
        // 1. Calculate the date range for today.
        let calendar = Calendar.current
        let today = Date()
        guard let startOfToday = calendar.startOfDay(for: today) as Date?,
              let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) as Date? else {
            print("Error: Could not calculate start and end of today.")
            return
        }
        
        // DEBUG: Print the date range we are searching.
        print("Searching for meetings from \(startOfToday) to \(endOfToday)")

        // 2. Get a list of all calendars the app can see.
        let availableCalendars = eventStore.calendars(for: .event)
        
        // DEBUG: Print the names of all available calendars.
        print("Available calendars:")
        for cal in availableCalendars {
            print("- \(cal.title)")
        }
        
        // 3. Create a predicate to find all events within our date range across all available calendars.
        let predicate = eventStore.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: availableCalendars)

        // 4. Fetch the events.
        let rawEvents = eventStore.events(matching: predicate)

        // DEBUG: Print how many events were found. THIS IS THE MOST IMPORTANT LINE.
        print("Found \(rawEvents.count) raw events matching the predicate.")

        // 5. Map the EKEvent objects to our simpler Meeting struct.
        self.meetings = rawEvents.map { event in
            Meeting(id: event.eventIdentifier, title: event.title, startDate: event.startDate)
        }
        
        print("Finished fetching. \(self.meetings.count) meetings loaded into the UI.")
        print("-----------------------------------------")
    }
}
