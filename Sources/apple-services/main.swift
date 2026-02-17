import Foundation
import EventKit
import Contacts

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

// MARK: - Contacts Service

struct ContactsService {
    let store = CNContactStore()

    static let fetchKeys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactIdentifierKey as CNKeyDescriptor,
    ]

    func requestAccess() {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        store.requestAccess(for: .contacts) { ok, _ in
            granted = ok
            semaphore.signal()
        }
        semaphore.wait()
        if !granted {
            errorOutput("Contacts access denied. Grant permission in System Settings > Privacy & Security.")
        }
    }

    // MARK: Actions

    func search(query: String) {
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let nameMatches: [CNContact]
        do {
            nameMatches = try store.unifiedContacts(matching: predicate, keysToFetch: Self.fetchKeys)
        } catch {
            errorOutput("Failed to search contacts: \(error.localizedDescription)")
        }

        // Also search by organization
        let lowerQuery = query.lowercased()
        var allContacts: [CNContact] = []
        let fetchRequest = CNContactFetchRequest(keysToFetch: Self.fetchKeys)
        do {
            try store.enumerateContacts(with: fetchRequest) { contact, _ in
                allContacts.append(contact)
            }
        } catch {
            errorOutput("Failed to enumerate contacts: \(error.localizedDescription)")
        }

        let nameIds = Set(nameMatches.map { $0.identifier })
        let orgMatches = allContacts.filter {
            !nameIds.contains($0.identifier) &&
            $0.organizationName.lowercased().contains(lowerQuery)
        }

        let results = (nameMatches + orgMatches).map { contactListDict($0) }
        jsonOutput(results)
    }

    func get(name: String) {
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let contacts: [CNContact]
        do {
            contacts = try store.unifiedContacts(matching: predicate, keysToFetch: Self.fetchKeys)
        } catch {
            errorOutput("Failed to get contact: \(error.localizedDescription)")
        }

        guard let contact = contacts.first else {
            errorOutput("Contact not found: \(name)")
        }

        jsonOutput(contactDetailDict(contact))
    }

    func list() {
        var results: [[String: Any]] = []
        let fetchRequest = CNContactFetchRequest(keysToFetch: Self.fetchKeys)
        fetchRequest.sortOrder = .familyName
        do {
            try store.enumerateContacts(with: fetchRequest) { contact, _ in
                results.append(contactListDict(contact))
            }
        } catch {
            errorOutput("Failed to list contacts: \(error.localizedDescription)")
        }
        jsonOutput(results)
    }

    func create(name: String, email: String?, phone: String?, organization: String?, birthday: String?) {
        let contact = CNMutableContact()

        let parts = name.split(separator: " ", maxSplits: 1)
        contact.givenName = String(parts[0])
        if parts.count > 1 {
            contact.familyName = String(parts[1])
        }

        if let email = email, !email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: email as NSString)]
        }
        if let phone = phone, !phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))]
        }
        if let org = organization, !org.isEmpty {
            contact.organizationName = org
        }
        if let birthday = birthday, !birthday.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // Try common formats
            for fmt in ["MMMM d, yyyy", "yyyy-MM-dd", "MM/dd/yyyy"] {
                formatter.dateFormat = fmt
                if let date = formatter.date(from: birthday) {
                    let components = Foundation.Calendar.current.dateComponents([.year, .month, .day], from: date)
                    contact.birthday = components
                    break
                }
            }
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(saveRequest)
        } catch {
            errorOutput("Failed to create contact: \(error.localizedDescription)")
        }
        jsonOutput(["message": "Contact created: \(name)"])
    }

    // MARK: Helpers

    private func fullName(_ contact: CNContact) -> String {
        [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func contactListDict(_ contact: CNContact) -> [String: Any] {
        [
            "name": fullName(contact),
            "email": contact.emailAddresses.map { $0.value as String },
            "phone": contact.phoneNumbers.map { $0.value.stringValue },
            "organization": contact.organizationName,
        ]
    }

    private func contactDetailDict(_ contact: CNContact) -> [String: Any] {
        var dict: [String: Any] = contactListDict(contact)
        if let bday = contact.birthday, let date = Foundation.Calendar.current.date(from: bday) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            dict["birthday"] = formatter.string(from: date)
        } else {
            dict["birthday"] = ""
        }
        return dict
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
    // Validate arguments before requesting TCC access
    switch action {
    case "list":
        break
    case "search":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services contacts search <query>") }
    case "get":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services contacts get <name>") }
    case "create":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services contacts create <name> [email] [phone] [organization] [birthday]") }
    default:
        errorOutput("Unknown contacts action: \(action)")
    }

    let contacts = ContactsService()
    contacts.requestAccess()

    switch action {
    case "search":
        contacts.search(query: remaining[0])
    case "get":
        contacts.get(name: remaining[0])
    case "list":
        contacts.list()
    case "create":
        let email = remaining.count >= 2 ? remaining[1] : nil
        let phone = remaining.count >= 3 ? remaining[2] : nil
        let org = remaining.count >= 4 ? remaining[3] : nil
        let birthday = remaining.count >= 5 ? remaining[4] : nil
        contacts.create(name: remaining[0], email: email, phone: phone, organization: org, birthday: birthday)
    default:
        break // already handled above
    }

default:
    usage()
}
