# apple-services-cli

Fast native macOS CLI for Apple Calendar and Contacts access. Replaces slow `osascript`-based shell scripts with direct EventKit and Contacts.framework integration.

## CLI Interface

All commands output JSON to stdout. Errors return `{"error": "..."}` with exit code 1.

### Calendar

```bash
# List all calendars
apple-services calendar list

# Get today's events
apple-services calendar today

# List events (optional: calendar name, days ahead; defaults to all calendars, 7 days)
apple-services calendar events [calendar] [days]

# Search events (required: query; optional: calendar, days)
apple-services calendar search <query> [calendar] [days]

# Create event (dates: "MM/DD/YYYY HH:MM:SS"; description optional)
apple-services calendar create <calendar> <title> <start> <end> [description]

# Get event details
apple-services calendar details <calendar> <title>

# Delete event
apple-services calendar delete <calendar> <title>
```

### Contacts

```bash
# Search contacts by name
apple-services contacts search <query>

# Get a specific contact by full name
apple-services contacts get <name>

# List all contacts
apple-services contacts list

# Create a contact (name required; rest optional)
apple-services contacts create <name> [email] [phone] [organization] [birthday]

# Delete a contact by name
apple-services contacts delete <name>
```

## JSON Output Format

### Calendar List
```json
[{"name": "Work", "color": "#1BADF8", "type": "CalDAV"}]
```

### Calendar Events
```json
[{"title": "Team Standup", "calendar": "Work", "start": "2025-01-15T09:00:00", "end": "2025-01-15T09:30:00", "location": "", "notes": "Daily standup", "allDay": false}]
```

### Contact
```json
{"name": "Jane Doe", "email": ["jane@example.com"], "phone": ["555-1234"], "organization": "Acme Corp", "birthday": "1990-01-15"}
```

### Contact List / Search
```json
[{"name": "Jane Doe", "email": ["jane@example.com"], "phone": ["555-1234"], "organization": "Acme Corp"}]
```

## Build & Install

```bash
swift build -c release
codesign --force --sign - --entitlements entitlements.plist .build/release/apple-services
sudo cp .build/release/apple-services /usr/local/bin/apple-services
```

The binary must be codesigned with `entitlements.plist` which declares calendar and contacts access entitlements. An `Info.plist` with the bundle identifier `com.nicknance.apple-services` is embedded via a linker flag in `Package.swift`.

## TCC Permissions

The binary requires macOS TCC (Transparency, Consent, and Control) grants for Calendar (Full Access) and Contacts. TCC attributes permissions to the **host terminal app** (e.g., Terminal.app, Warp, iTerm), not the binary itself. The terminal app must have Calendar and Contacts access granted in **System Settings > Privacy & Security**. On first run from a new terminal app, macOS should prompt for access.

## Architecture

- **EventKit** for all calendar operations (read/write/delete events, list calendars)
- **Contacts.framework** for all contact operations (search, get, list, create)
- **Foundation** `JSONSerialization` for output
- Single binary, subcommand-based CLI (no external dependencies)
- Argument signatures match the existing shell scripts for drop-in replacement
