# Implementation Plan

Step-by-step plan for building the `apple-services` Swift CLI. This replaces the `osascript`-based shell scripts in `claude-assistant` with native framework calls.

## Current Shell Script Behavior (to replicate exactly)

### Delimiters & Parsing
The shell scripts use AppleScript via `osascript`, serialize with custom delimiters (`|||` for fields, `:::` for records), then parse to JSON with `awk`. The Swift CLI eliminates all of this by using `JSONSerialization` directly.

### Calendar Commands

| Command | Shell behavior | Swift equivalent |
|---------|---------------|-----------------|
| `list` | Returns JSON array of calendar name strings: `["Work", "Personal"]` | `EKEventStore.calendars(for: .event)` → map to names |
| `today` | Alias for `events <default> 1` | Same logic, 1-day window |
| `events [cal] [days]` | Fetches events from a named calendar within a date range. Defaults: calendar from `$APPLE_CALENDAR_NAME` or `"Calendar"`, 7 days. Returns `[{summary, startDate, endDate, calendar}]` | `EKEventStore.events(matching:)` with predicate |
| `search <q> [cal] [days]` | Like `events` but filters by summary/description containing query. Default 90 days. Same output format | Same predicate + client-side or predicate filter on summary |
| `create <cal> <title> <start> <end> [desc]` | Creates event. Dates formatted as `"MM/DD/YYYY HH:MM:SS"`. Returns `{message: "Event created: ..."}` | `EKEvent` + `EKEventStore.save()` |
| `details <cal> <title>` | Finds first event matching title in calendar. Returns `{summary, startDate, endDate, calendar, description, location, url}` | `events(matching:)` + filter by title, return first match |
| `delete <cal> <title>` | Finds and deletes first event matching title. Returns `{message: "Event deleted/not found: ..."}` | `events(matching:)` + `EKEventStore.remove()` |

### Contacts Commands

| Command | Shell behavior | Swift equivalent |
|---------|---------------|-----------------|
| `search <q>` | Iterates all contacts, matches name or organization containing query. Returns `[{id, name, emails[], phones[], organization?, birthday?}]` | `CNContactStore.unifiedContacts(matching:)` with compound predicate |
| `get <name>` | Exact name match, returns single contact object (same fields) | `CNContact.predicateForContacts(matchingName:)` |
| `list` | All contacts, same format as search results | `CNContactStore.enumerateContacts` |
| `create <name> [email] [phone] [org] [birthday]` | Creates contact with optional fields. Birthday as string `"January 15, 1990"`. Returns `{message: "Contact created: ..."}` | `CNMutableContact` + `CNSaveRequest` |

## Implementation Steps

### Step 1: Project scaffolding
- Flesh out `Package.swift` with proper dependencies (none needed — EventKit and Contacts are system frameworks)
- Set up `main.swift` with argument parsing (use `CommandLine.arguments`, no external deps)
- Implement top-level dispatch: `calendar <action>` / `contacts <action>`
- Add JSON output helper: `func jsonOutput(_ dict: [String: Any])` using `JSONSerialization`
- Add error output helper: `func errorOutput(_ message: String) -> Never`

### Step 2: Calendar — EventKit integration
- Request calendar access with `EKEventStore.requestFullAccessToEvents()`
- Implement `CalendarService` struct with methods for each action
- Date parsing: accept `"MM/DD/YYYY HH:MM:SS"` format (matching shell scripts)
- Date output: ISO 8601 format for JSON responses
- Calendar lookup by name: `eventStore.calendars(for: .event).first(where: { $0.title == name })`
- Default calendar: read `APPLE_CALENDAR_NAME` env var, fall back to `"Calendar"`

#### Calendar methods:
1. `list()` → `[String]` array of calendar names
2. `events(calendar: String?, days: Int)` → predicate-based fetch, map to JSON
3. `search(query: String, calendar: String?, days: Int)` → events + filter by title/notes containing query
4. `create(calendar: String, title: String, start: Date, end: Date, description: String?)` → `EKEvent` + save
5. `details(calendar: String, title: String)` → fetch + filter, return full fields
6. `delete(calendar: String, title: String)` → fetch + filter + remove
7. `today()` → `events(calendar: default, days: 1)`

### Step 3: Contacts — Contacts.framework integration
- Request contacts access with `CNContactStore.requestAccess(for: .contacts)`
- Implement `ContactsService` struct
- Define fetch keys: `[.givenName, .familyName, .emailAddresses, .phoneNumbers, .organizationName, .birthday, .identifier]`

#### Contacts methods:
1. `search(query: String)` → `CNContact.predicateForContacts(matchingName:)` + also check org
2. `get(name: String)` → `predicateForContacts(matchingName:)`, return first exact match
3. `list()` → `enumerateContacts(with:)` over all contacts
4. `create(name: String, email: String?, phone: String?, org: String?, birthday: String?)` → `CNMutableContact` + `CNSaveRequest`

### Step 4: JSON output format
Ensure output matches what the shell scripts produce so downstream consumers (the agent) don't break.

**Calendar list:** `["Work", "Personal"]`

**Calendar events/search:**
```json
[
  {"summary": "...", "startDate": "2025-01-15T09:00:00", "endDate": "2025-01-15T09:30:00", "calendar": "Work"}
]
```

**Calendar details:**
```json
{"summary": "...", "startDate": "...", "endDate": "...", "calendar": "...", "description": "...", "location": "...", "url": "..."}
```

**Calendar create/delete:** `{"message": "Event created: ..."}`

**Contacts (get/search/list):**
```json
[
  {"id": "...", "name": "Jane Doe", "emails": ["jane@example.com"], "phones": ["555-1234"], "organization": "Acme Corp", "birthday": "..."}
]
```

**Contacts create:** `{"message": "Contact created: ..."}`

**Errors (all):** `{"error": "..."}` with exit code 1

### Step 5: Error handling
- TCC denial → `{"error": "Calendar/Contacts access denied. Grant permission in System Settings > Privacy & Security."}`
- Calendar not found → `{"error": "Calendar not found: <name>"}`
- Event not found → `{"error": "Event not found: <title>"}`
- Contact not found → `{"error": "Contact not found: <name>"}`
- Invalid date format → `{"error": "Invalid date format. Expected: MM/DD/YYYY HH:MM:SS"}`
- Unknown action → usage text to stderr, exit 1

### Step 6: Build, codesign, install
```bash
swift build -c release
codesign --force --sign - .build/release/apple-services
cp .build/release/apple-services /usr/local/bin/apple-services
```

## Testing Strategy
- Build and run each command manually against real Calendar and Contacts data
- Compare JSON output with existing shell script output for the same data
- Verify TCC prompts appear correctly on first run
- Verify error cases (missing calendar, missing contact, bad date format)

## Key Differences from Shell Scripts
- **Performance**: Single binary, no subprocess spawning, no `osascript` overhead
- **Date output**: ISO 8601 (`2025-01-15T09:00:00`) instead of AppleScript's locale-dependent date strings
- **JSON**: Proper `JSONSerialization` instead of `awk`-based string assembly (handles special chars correctly)
- **Search**: Contacts.framework supports indexed predicate search instead of linear iteration over all contacts
