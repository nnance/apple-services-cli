import Foundation
import EventKit

// MARK: - JSON Output Helpers

func jsonOutput(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        errorOutput("Failed to serialize JSON")
    }
    print(string)
}

func errorOutput(_ message: String) -> Never {
    let data = try! JSONSerialization.data(withJSONObject: ["error": message])
    FileHandle.standardError.write(data)
    FileHandle.standardError.write("\n".data(using: .utf8)!)
    exit(1)
}

func usage() -> Never {
    let text = """
    Usage: apple-services <service> <action> [args...]

    Services:
      calendar  list | today | events [calendar] [days] | search <query> [calendar] [days]
                create <calendar> <title> <start> <end> [description]
                details <calendar> <title> | delete <calendar> <title>
      contacts  search <query> | get <name> | list
                create <name> [email] [phone] [organization] [birthday]
    """
    FileHandle.standardError.write(text.data(using: .utf8)!)
    exit(1)
}

// MARK: - Date Helpers

let isoFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

let inputFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MM/dd/yyyy HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

func parseInputDate(_ string: String) -> Date {
    guard let date = inputFormatter.date(from: string) else {
        errorOutput("Invalid date format. Expected: MM/DD/YYYY HH:MM:SS")
    }
    return date
}

// MARK: - Calendar Service

struct CalendarService {
    let store = EKEventStore()

    func requestAccess() {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents { ok, _ in
                granted = ok
                semaphore.signal()
            }
        } else {
            store.requestAccess(to: .event) { ok, _ in
                granted = ok
                semaphore.signal()
            }
        }
        semaphore.wait()
        if !granted {
            errorOutput("Calendar access denied. Grant permission in System Settings > Privacy & Security.")
        }
    }

    func findCalendar(_ name: String) -> EKCalendar {
        guard let cal = store.calendars(for: .event).first(where: { $0.title == name }) else {
            errorOutput("Calendar not found: \(name)")
        }
        return cal
    }

    var defaultCalendarName: String {
        ProcessInfo.processInfo.environment["APPLE_CALENDAR_NAME"] ?? "Calendar"
    }

    // MARK: Actions

    func list() {
        let calendars = store.calendars(for: .event).map { cal -> [String: Any] in
            var colorHex = ""
            if let cgColor = cal.cgColor {
                let comps = cgColor.components ?? []
                if comps.count >= 3 {
                    let r = Int(comps[0] * 255)
                    let g = Int(comps[1] * 255)
                    let b = Int(comps[2] * 255)
                    colorHex = String(format: "#%02X%02X%02X", r, g, b)
                }
            }
            return [
                "name": cal.title,
                "color": colorHex,
                "type": cal.source?.sourceType.description ?? "unknown"
            ]
        }
        jsonOutput(calendars)
    }

    func events(calendarName: String?, days: Int) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!

        var calendars: [EKCalendar]? = nil
        if let name = calendarName {
            calendars = [findCalendar(name)]
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)
        jsonOutput(events.map { eventDict($0) })
    }

    func search(query: String, calendarName: String?, days: Int) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: days, to: start)!

        var calendars: [EKCalendar]? = nil
        if let name = calendarName {
            calendars = [findCalendar(name)]
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let lowerQuery = query.lowercased()
        let events = store.events(matching: predicate).filter { event in
            (event.title?.lowercased().contains(lowerQuery) ?? false) ||
            (event.notes?.lowercased().contains(lowerQuery) ?? false)
        }
        jsonOutput(events.map { eventDict($0) })
    }

    func create(calendarName: String, title: String, start: Date, end: Date, description: String?) {
        let cal = findCalendar(calendarName)
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = description
        event.calendar = cal
        do {
            try store.save(event, span: .thisEvent)
        } catch {
            errorOutput("Failed to create event: \(error.localizedDescription)")
        }
        jsonOutput(["message": "Event created: \(title)"])
    }

    func details(calendarName: String, title: String) {
        let cal = findCalendar(calendarName)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .year, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
        let events = store.events(matching: predicate)

        guard let event = events.first(where: { $0.title == title }) else {
            errorOutput("Event not found: \(title)")
        }

        let dict: [String: Any] = [
            "title": event.title ?? "",
            "calendar": event.calendar.title,
            "start": isoFormatter.string(from: event.startDate),
            "end": isoFormatter.string(from: event.endDate),
            "location": event.location ?? "",
            "notes": event.notes ?? "",
            "url": event.url?.absoluteString ?? "",
            "allDay": event.isAllDay
        ]
        jsonOutput(dict)
    }

    func delete(calendarName: String, title: String) {
        let cal = findCalendar(calendarName)
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .year, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
        let events = store.events(matching: predicate)

        guard let event = events.first(where: { $0.title == title }) else {
            jsonOutput(["message": "Event not found: \(title)"])
            return
        }

        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            errorOutput("Failed to delete event: \(error.localizedDescription)")
        }
        jsonOutput(["message": "Event deleted: \(title)"])
    }

    // MARK: Helpers

    private func eventDict(_ event: EKEvent) -> [String: Any] {
        [
            "title": event.title ?? "",
            "calendar": event.calendar.title,
            "start": isoFormatter.string(from: event.startDate),
            "end": isoFormatter.string(from: event.endDate),
            "location": event.location ?? "",
            "notes": event.notes ?? "",
            "allDay": event.isAllDay
        ]
    }
}

// MARK: - EKSourceType description

extension EKSourceType: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .local: return "Local"
        case .exchange: return "Exchange"
        case .calDAV: return "CalDAV"
        case .mobileMe: return "MobileMe"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Argument Parsing & Dispatch

let args = Array(CommandLine.arguments.dropFirst())

guard args.count >= 2 else {
    usage()
}

let service = args[0]
let action = args[1]
let remaining = Array(args.dropFirst(2))

switch service {
case "calendar":
    // Validate arguments before requesting TCC access
    switch action {
    case "list", "today", "events":
        break
    case "search":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services calendar search <query> [calendar] [days]") }
    case "create":
        guard remaining.count >= 4 else { errorOutput("Usage: apple-services calendar create <calendar> <title> <start> <end> [description]") }
    case "details":
        guard remaining.count >= 2 else { errorOutput("Usage: apple-services calendar details <calendar> <title>") }
    case "delete":
        guard remaining.count >= 2 else { errorOutput("Usage: apple-services calendar delete <calendar> <title>") }
    default:
        errorOutput("Unknown calendar action: \(action)")
    }

    let cal = CalendarService()
    cal.requestAccess()

    switch action {
    case "list":
        cal.list()
    case "today":
        cal.events(calendarName: nil, days: 1)
    case "events":
        let name = remaining.count >= 1 ? remaining[0] : nil
        let days = remaining.count >= 2 ? (Int(remaining[1]) ?? 7) : 7
        cal.events(calendarName: name, days: days)
    case "search":
        let query = remaining[0]
        let name = remaining.count >= 2 ? remaining[1] : nil
        let days = remaining.count >= 3 ? (Int(remaining[2]) ?? 90) : 90
        cal.search(query: query, calendarName: name, days: days)
    case "create":
        let start = parseInputDate(remaining[2])
        let end = parseInputDate(remaining[3])
        let desc = remaining.count >= 5 ? remaining[4] : nil
        cal.create(calendarName: remaining[0], title: remaining[1], start: start, end: end, description: desc)
    case "details":
        cal.details(calendarName: remaining[0], title: remaining[1])
    case "delete":
        cal.delete(calendarName: remaining[0], title: remaining[1])
    default:
        break // already handled above
    }

case "contacts":
    switch action {
    case "search":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services contacts search <query>") }
        errorOutput("Contacts search not yet implemented")
    case "get":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services contacts get <name>") }
        errorOutput("Contacts get not yet implemented")
    case "list":
        errorOutput("Contacts list not yet implemented")
    case "create":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services contacts create <name> [email] [phone] [organization] [birthday]") }
        errorOutput("Contacts create not yet implemented")
    default:
        errorOutput("Unknown contacts action: \(action)")
    }

default:
    usage()
}
