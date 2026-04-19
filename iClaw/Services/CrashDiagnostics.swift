import Foundation

/// Persists the most recent NSException `name`/`reason` to UserDefaults so the
/// next launch can log it. Crash-safe — UserDefaults writes are flushed by the
/// OS even when the process terminates abnormally.
///
/// Intentionally does NOT alter, reset, or delete the SwiftData store. This
/// type is diagnostic-only: it captures what went wrong so we can identify the
/// trigger of future occurrences, without changing any user data.
enum CrashDiagnostics {
    private static let key = "iClaw.lastNSException"

    struct Record: Codable {
        let source: String
        let name: String
        let reason: String
        let timestamp: Date
    }

    static func record(source: String, name: String, reason: String) {
        let record = Record(source: source, name: name, reason: reason, timestamp: Date())
        if let data = try? JSONEncoder().encode(record) {
            UserDefaults.standard.set(data, forKey: key)
        }
        print("[CrashDiagnostics] \(source): \(name) — \(reason)")
    }

    static func consume() -> Record? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(Record.self, from: data)
        else { return nil }
        UserDefaults.standard.removeObject(forKey: key)
        return record
    }
}
