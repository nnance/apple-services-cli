import Foundation

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
    switch action {
    case "list":
        errorOutput("Calendar list not yet implemented")
    case "today":
        errorOutput("Calendar today not yet implemented")
    case "events":
        errorOutput("Calendar events not yet implemented")
    case "search":
        guard remaining.count >= 1 else { errorOutput("Usage: apple-services calendar search <query> [calendar] [days]") }
        errorOutput("Calendar search not yet implemented")
    case "create":
        guard remaining.count >= 4 else { errorOutput("Usage: apple-services calendar create <calendar> <title> <start> <end> [description]") }
        errorOutput("Calendar create not yet implemented")
    case "details":
        guard remaining.count >= 2 else { errorOutput("Usage: apple-services calendar details <calendar> <title>") }
        errorOutput("Calendar details not yet implemented")
    case "delete":
        guard remaining.count >= 2 else { errorOutput("Usage: apple-services calendar delete <calendar> <title>") }
        errorOutput("Calendar delete not yet implemented")
    default:
        errorOutput("Unknown calendar action: \(action)")
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
