import Foundation

enum SSEEvent {
    case message(data: String)
    case done
}

struct SSEParser {
    private var buffer = ""

    mutating func parse(chunk: String) -> [SSEEvent] {
        buffer += chunk
        var events: [SSEEvent] = []

        while let range = buffer.range(of: "\n\n") {
            let eventBlock = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            var data = ""
            for line in eventBlock.components(separatedBy: "\n") {
                if line.hasPrefix("data: ") {
                    let value = String(line.dropFirst(6))
                    if value == "[DONE]" {
                        events.append(.done)
                        return events
                    }
                    if !data.isEmpty { data += "\n" }
                    data += value
                } else if line == "data:" {
                    if !data.isEmpty { data += "\n" }
                }
            }

            if !data.isEmpty {
                events.append(.message(data: data))
            }
        }

        return events
    }

    mutating func reset() {
        buffer = ""
    }
}
