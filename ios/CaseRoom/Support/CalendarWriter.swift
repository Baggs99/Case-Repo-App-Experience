/*
 * Purpose: Writes accepted practice sessions into the user's default
 *          calendar via EventKit's write-only entitlement.
 * Inputs: EKEventStore (write-only access requested at call time).
 * Outputs: an EKEvent saved to the device's default calendar.
 * Run: consumed by SessionsViewModel.accept(_:at:) as CalendarAdding.
 */

import EventKit
import Foundation

protocol CalendarAdding {
    func add(title: String, startDate: Date, notes: String?) async throws
}

enum CalendarWriterError: Error {
    case accessDenied
}

struct EventKitCalendarWriter: CalendarAdding {
    private let store = EKEventStore()

    func add(title: String, startDate: Date, notes: String?) async throws {
        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else {
            throw CalendarWriterError.accessDenied
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(45 * 60)
        event.notes = notes
        event.calendar = store.defaultCalendarForNewEvents
        event.addAlarm(EKAlarm(relativeOffset: -15 * 60))

        try store.save(event, span: .thisEvent)
    }
}
