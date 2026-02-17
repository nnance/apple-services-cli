# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Native macOS CLI (Swift) that provides fast access to Apple Calendar and Contacts. Replaces slow `osascript`-based shell scripts with direct EventKit and Contacts.framework calls. Single binary, no external dependencies.

## Build & Run

```bash
swift build                    # Debug build
swift build -c release         # Release build

# Install (release)
codesign --force --sign - .build/release/apple-services
cp .build/release/apple-services /usr/local/bin/apple-services

# Run (debug)
.build/debug/apple-services calendar list
.build/debug/apple-services contacts search "Jane"
```

No test suite or linter is configured. Test manually by running subcommands against real Calendar/Contacts data.

## Architecture

- **Swift Package Manager** project (swift-tools-version 5.9, macOS 13+)
- **Single entry point**: `Sources/apple-services/main.swift`
- **Subcommand dispatch**: `apple-services <service> <action> [args...]` where service is `calendar` or `contacts`
- **Argument parsing**: Raw `CommandLine.arguments` (no ArgumentParser dependency)
- **Frameworks**: EventKit (calendar ops), Contacts.framework (contact ops), Foundation (JSON, dates)

### Key Services

- **CalendarService** — wraps `EKEventStore` for list/today/events/search/create/details/delete
- **ContactsService** — wraps `CNContactStore` for search/get/list/create

### Output Conventions

- All output is JSON to stdout via `JSONSerialization`
- Errors: `{"error": "..."}` with exit code 1
- Success messages (create/delete): `{"message": "..."}`
- Date input format: `"MM/DD/YYYY HH:MM:SS"`
- Date output format: ISO 8601
- Default calendar: `$APPLE_CALENDAR_NAME` env var, fallback `"Calendar"`

### TCC Permissions

The binary requires macOS TCC grants for Calendar (Full Access) and Contacts. The host terminal app must also have these permissions (System Settings > Privacy & Security).

## Implementation Reference

See `PLAN.md` for the detailed implementation roadmap, including exact JSON output schemas that must match the shell scripts being replaced and all error handling cases.
