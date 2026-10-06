import Foundation

/// A JSON value that keeps object keys in file order, so Turnring can edit an agent's
/// config file without reordering the user's settings.
indirect enum JSON: Equatable {
    case object([Member])
    case array([JSON])
    case string(String)
    case number(String) // kept as written
    case bool(Bool)
    case null

    struct Member: Equatable {
        var key: String
        var value: JSON
    }

    struct ParseError: Error {}

    // MARK: Access

    subscript(key: String) -> JSON? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(Member(key: key, value: newValue))
            }
            self = .object(members)
        }
    }

    var array: [JSON]? { if case .array(let items) = self { items } else { nil } }
    var string: String? { if case .string(let text) = self { text } else { nil } }
    var isObject: Bool { if case .object = self { true } else { false } }
    var keys: [String] { if case .object(let members) = self { members.map(\.key) } else { [] } }

    // MARK: Parsing

    static func parse(_ data: Data) throws -> JSON {
        var parser = Parser(bytes: Array(data))
        let value = try parser.value()
        parser.skipSpace()
        guard parser.index == parser.bytes.count else { throw ParseError() }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        mutating func skipSpace() {
            while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
        }

        mutating func value() throws -> JSON {
            skipSpace()
            guard index < bytes.count else { throw ParseError() }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws {
            let w = Array(word.utf8)
            guard index + w.count <= bytes.count, Array(bytes[index..<index + w.count]) == w else { throw ParseError() }
            index += w.count
        }

        mutating func object() throws -> JSON {
            index += 1
            var members: [Member] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            while true {
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw ParseError() }
                let key = try string()
                skipSpace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw ParseError() }
                index += 1
                members.append(Member(key: key, value: try value()))
                skipSpace()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw ParseError()
            }
        }

        mutating func array() throws -> JSON {
            index += 1
            var items: [JSON] = []
            skipSpace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                items.append(try value())
                skipSpace()
                guard index < bytes.count else { throw ParseError() }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw ParseError()
            }
        }

        mutating func string() throws -> String {
            // Find the closing quote, then let JSONDecoder handle escapes and Unicode.
            let start = index
            index += 1
            while index < bytes.count {
                if bytes[index] == UInt8(ascii: "\\") { index += 2; continue }
                if bytes[index] == UInt8(ascii: "\"") {
                    index += 1
                    let literal = Data(bytes[start..<index])
                    guard let text = try? JSONDecoder().decode(String.self, from: literal) else { throw ParseError() }
                    return text
                }
                index += 1
            }
            throw ParseError()
        }

        mutating func number() throws -> JSON {
            let start = index
            let allowed = Set("+-0123456789.eE".utf8)
            while index < bytes.count, allowed.contains(bytes[index]) { index += 1 }
            guard index > start, let text = String(bytes: bytes[start..<index], encoding: .utf8),
                  Double(text) != nil else { throw ParseError() }
            return .number(text)
        }
    }

    // MARK: Writing

    /// Pretty-printed with two-space indents, the layout Claude Code and Codex use.
    func serialized() -> Data {
        var out = ""
        write(into: &out, indent: "")
        return Data((out + "\n").utf8)
    }

    private func write(into out: inout String, indent: String) {
        let inner = indent + "  "
        switch self {
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += inner + JSON.quote(member.key) + ": "
                member.value.write(into: &out, indent: inner)
                out += i < members.count - 1 ? ",\n" : "\n"
            }
            out += indent + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += inner
                item.write(into: &out, indent: inner)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += indent + "]"
        case .string(let text): out += JSON.quote(text)
        case .number(let text): out += text
        case .bool(let flag): out += flag ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quote(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
