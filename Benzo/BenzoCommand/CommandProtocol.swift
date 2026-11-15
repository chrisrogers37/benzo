import Darwin
import Foundation

/// Resolved from the invoking account by the OS adapter, never from JSON input.
struct PowerCommandOwner: Codable, Equatable {
    let uid: UInt32
    let generatedUID: UUID

    func validate() throws {
        guard uid != 0, generatedUID != PowerCommandWire.zeroUUID else {
            throw PowerCommandError.invalid("The setup account could not be identified.")
        }
    }
}

struct PowerCommandToken: Codable, Equatable {
    var schema = 1
    var protocolVersion = 1
    let grantEpoch: UUID
    let sequence: UInt64
    let requestID: UUID

    enum CodingKeys: String, CodingKey { case schema, protocolVersion = "protocol", grantEpoch, sequence, requestID }

    func validate() throws {
        guard schema == 1, protocolVersion == 1, sequence > 0,
              grantEpoch != PowerCommandWire.zeroUUID, requestID != PowerCommandWire.zeroUUID else {
            throw PowerCommandError.invalid("The command token is invalid or unsupported.")
        }
    }
}

/// Flat, bounded input. There are exactly 45 allowed (profile, key, target)
/// combinations; the expected value must independently belong to the key domain.
struct PowerCommandRequest: Codable, Equatable {
    var schema = 1
    var protocolVersion = 1
    let grantEpoch: UUID
    let sequence: UInt64
    let requestID: UUID
    let operationID: UUID
    let bootID: UUID
    let profile: PowerProfile
    let key: ManagedKey
    let expectedValue: Int
    let target: Int

    enum CodingKeys: String, CodingKey {
        case schema, protocolVersion = "protocol", grantEpoch, sequence, requestID, operationID, bootID
        case profile, key, expectedValue, target
    }

    var cell: ManagedCell { ManagedCell(profile: profile, key: key) }
    var token: PowerCommandToken {
        PowerCommandToken(schema: schema, protocolVersion: protocolVersion,
                          grantEpoch: grantEpoch, sequence: sequence, requestID: requestID)
    }

    func validate() throws {
        try token.validate()
        guard operationID != PowerCommandWire.zeroUUID, bootID != PowerCommandWire.zeroUUID,
              key.isValid(expectedValue), key.isValid(target) else {
            throw PowerCommandError.invalid("The command identity or setting value is invalid.")
        }
    }
}

/// Sleep is a distinct operation, never a setting tuple or a scheduled root job.
struct PowerSleepRequest: Codable, Equatable {
    var schema = 1
    var protocolVersion = 1
    let grantEpoch: UUID
    let sequence: UInt64
    let requestID: UUID
    let operationID: UUID
    let bootID: UUID
    let expiresAtContinuousTicks: UInt64

    enum CodingKeys: String, CodingKey {
        case schema, protocolVersion = "protocol", grantEpoch, sequence, requestID, operationID, bootID
        case expiresAtContinuousTicks
    }
    var token: PowerCommandToken {
        PowerCommandToken(schema: schema, protocolVersion: protocolVersion,
                          grantEpoch: grantEpoch, sequence: sequence, requestID: requestID)
    }
    func validate() throws {
        try token.validate()
        guard operationID != PowerCommandWire.zeroUUID, bootID != PowerCommandWire.zeroUUID,
              expiresAtContinuousTicks > 0 else {
            throw PowerCommandError.invalid("The sleep command identity or expiry is invalid.")
        }
    }
}

enum PowerSleepReceiptOutcome: Codable, Equatable {
    case intent
    /// Records only the owned command's exit, never proof of physical sleep.
    case completed(exitStatus: Int)
    case notExecuted(reason: String)
    case childStoppedOutcomeUnknown(reason: String)
    /// The prior-boot child cannot remain alive. Its sleep result is unknown.
    case reconciledAfterBoot
}

struct PowerSleepReceipt: Codable, Equatable {
    let request: PowerSleepRequest
    var outcome: PowerSleepReceiptOutcome
    var isTerminal: Bool { if case .intent = outcome { return false }; return true }
    func validate() throws {
        try request.validate()
        switch outcome {
        case .intent, .reconciledAfterBoot: break
        case .completed(let status):
            guard (0...255).contains(status) else { throw PowerCommandError.invalid("Invalid sleep child exit status.") }
        case .notExecuted(let reason), .childStoppedOutcomeUnknown(let reason):
            try PowerCommandWire.validateReason(reason)
        }
    }
}

enum PowerSleepExecution: Equatable {
    case completed(exitStatus: Int)
    case notExecuted(reason: String)
    case childStoppedOutcomeUnknown(reason: String)
    case uncertain(reason: String)
}

/// mach_continuous_time includes system sleep. Wall-clock changes cannot revive
/// a delayed request, and the root command accepts at most thirty seconds ahead.
enum PowerSleepClock {
    static func now() -> UInt64 { mach_continuous_time() }
    static func ticks(seconds: UInt64) -> UInt64 {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.numer > 0, info.denom > 0 else { return 0 }
        let nanoseconds = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        guard !nanoseconds.overflow else { return 0 }
        let product = nanoseconds.partialValue.multipliedReportingOverflow(by: UInt64(info.denom))
        guard !product.overflow else { return 0 }
        return product.partialValue / UInt64(info.numer)
    }
    static func admits(expiry: UInt64, now: UInt64, maximumLifetime: UInt64) -> Bool {
        maximumLifetime > 0 && expiry > now && expiry - now <= maximumLifetime
    }
}

enum PowerCommandVerb: String, CaseIterable {
    case write = "write-v1", status = "status-v1", ack = "ack-v1", seal = "seal-v1", version = "version-v1"
    case sleep = "sleep-v1", sealSleep = "seal-sleep-v1"
}

enum PowerCommandInput: Equatable {
    case write(PowerCommandRequest), seal(PowerCommandRequest)
    case sleep(PowerSleepRequest), sealSleep(PowerSleepRequest)
    case status(PowerCommandToken), ack(PowerCommandToken)
    case version
}

enum PowerCommandReceiptOutcome: Codable, Equatable {
    case intent
    case completed(exitStatus: Int)
    case notExecuted(reason: String)
    /// A later boot and explicit read-only capture settle the live-child fence,
    /// without claiming how the old write terminated or whether it took effect.
    case reconciledAfterBoot(observedValue: Int)
}

struct PowerCommandReceipt: Codable, Equatable {
    let request: PowerCommandRequest
    var outcome: PowerCommandReceiptOutcome
    var isTerminal: Bool { if case .intent = outcome { return false }; return true }

    func validate() throws {
        try request.validate()
        switch outcome {
        case .intent: break
        case .completed(let status):
            guard (0...255).contains(status) else { throw PowerCommandError.invalid("Invalid child exit status.") }
        case .notExecuted(let reason): try PowerCommandWire.validateReason(reason)
        case .reconciledAfterBoot(let value):
            guard request.key.isValid(value) else { throw PowerCommandError.invalid("Invalid reconciled setting value.") }
        }
    }
}

struct PowerCommandState: Codable, Equatable {
    var schema = 1
    let owner: PowerCommandOwner
    let grantEpoch: UUID
    var highWaterMark: UInt64
    var pending: PowerCommandReceipt?
    var pendingSleep: PowerSleepReceipt?

    private enum CodingKeys: String, CodingKey { case schema, owner, grantEpoch, highWaterMark, pending, pendingSleep }

    init(schema: Int = 1, owner: PowerCommandOwner, grantEpoch: UUID,
         highWaterMark: UInt64, pending: PowerCommandReceipt?, pendingSleep: PowerSleepReceipt? = nil) {
        self.schema = schema; self.owner = owner; self.grantEpoch = grantEpoch
        self.highWaterMark = highWaterMark; self.pending = pending; self.pendingSleep = pendingSleep
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        schema = try fields.decode(Int.self, forKey: .schema)
        owner = try fields.decode(PowerCommandOwner.self, forKey: .owner)
        grantEpoch = try fields.decode(UUID.self, forKey: .grantEpoch)
        highWaterMark = try fields.decode(UInt64.self, forKey: .highWaterMark)
        // Missing receipt evidence is different from an explicit acknowledged
        // empty slot. Do not let decodeIfPresent turn missing evidence into ACK.
        pending = try fields.decode(PowerCommandReceipt?.self, forKey: .pending)
        guard schema == 2 || !fields.contains(.pendingSleep) else {
            throw PowerCommandError.invalid("Sleep evidence requires authority schema 2.")
        }
        pendingSleep = schema == 2 ? try fields.decode(PowerSleepReceipt.self, forKey: .pendingSleep) : nil
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(schema, forKey: .schema); try fields.encode(owner, forKey: .owner)
        try fields.encode(grantEpoch, forKey: .grantEpoch); try fields.encode(highWaterMark, forKey: .highWaterMark)
        try fields.encode(pending, forKey: .pending)
        if schema == 2 { try fields.encode(pendingSleep, forKey: .pendingSleep) }
    }

    static func initial(owner: PowerCommandOwner, grantEpoch: UUID = UUID()) throws -> Self {
        let state = Self(owner: owner, grantEpoch: grantEpoch, highWaterMark: 0, pending: nil)
        try state.validate()
        return state
    }

    func validate() throws {
        try owner.validate()
        guard (schema == 1 && pendingSleep == nil) || (schema == 2 && pending == nil && pendingSleep != nil),
              grantEpoch != PowerCommandWire.zeroUUID else {
            throw PowerCommandError.invalid("Unsupported command authority state.")
        }
        if let pending {
            try pending.validate()
            guard pending.request.grantEpoch == grantEpoch, pending.request.sequence == highWaterMark else {
                throw PowerCommandError.invalid("The receipt does not match the command watermark.")
            }
        }
        if let pendingSleep {
            try pendingSleep.validate()
            guard pendingSleep.request.grantEpoch == grantEpoch, pendingSleep.request.sequence == highWaterMark else {
                throw PowerCommandError.invalid("The sleep receipt does not match the command watermark.")
            }
        }
    }

    /// Storage also enforces transitions, so callers cannot replace evidence or
    /// release an intent by writing an otherwise structurally valid state.
    func validateTransition(from old: Self) throws {
        try old.validate()
        try validate()
        guard owner == old.owner, grantEpoch == old.grantEpoch else {
            throw PowerCommandError.invalid("The command grant cannot be replaced.")
        }
        if self == old { return }
        if highWaterMark == old.highWaterMark {
            if schema == 1, old.schema == 1 {
                if let previous = old.pending, let next = pending,
                   previous.request == next.request, !previous.isTerminal, next.isTerminal { return }
                if old.pending?.isTerminal == true, pending == nil { return }
            }
            if schema == 2, old.schema == 2, let previous = old.pendingSleep, let next = pendingSleep,
               previous.request == next.request, !previous.isTerminal, next.isTerminal { return }
            if old.schema == 2, old.pendingSleep?.isTerminal == true, schema == 1,
               pending == nil, pendingSleep == nil { return }
        } else if old.highWaterMark < UInt64.max, highWaterMark == old.highWaterMark + 1,
                  old.schema == 1, old.pending == nil {
            // New admission may only record intent or a durable no-spawn seal.
            if let pending {
                switch pending.outcome { case .intent, .notExecuted: return; default: break }
            }
            if let pendingSleep {
                switch pendingSleep.outcome { case .intent, .notExecuted: return; default: break }
            }
        }
        throw PowerCommandError.invalid("The command transition would replace or discard execution evidence.")
    }
}

enum PowerCommandExecution: Equatable {
    /// The adapter has waited for its one owned child and proved terminal exit.
    case completed(exitStatus: Int)
    /// The adapter proved no child was spawned.
    case notExecuted(reason: String)
    case uncertain(reason: String)
}

enum PowerCommandDisposition: Codable, Equatable {
    case completed(exitStatus: Int), notExecuted(reason: String), uncertain(reason: String), denied(reason: String)
    case differentAccount
    case reconciledAfterBoot(observedValue: Int)
    case acknowledged, version
}

struct PowerCommandReply: Codable, Equatable {
    var schema = 1
    var protocolVersion = 1
    let token: PowerCommandToken?
    let request: PowerCommandRequest?
    let owner: PowerCommandOwner?
    let grantEpoch: UUID?
    let highWaterMark: UInt64?
    let bootID: UUID?
    let pending: PowerCommandReceipt?
    let outcome: PowerCommandDisposition
    var sleepRequest: PowerSleepRequest? = nil
    var pendingSleep: PowerSleepReceipt? = nil
    var capabilities: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case schema, protocolVersion = "protocol", token, request, owner, grantEpoch, highWaterMark, bootID, pending, outcome
        case sleepRequest, pendingSleep, capabilities
    }
}

protocol PowerCommandStoring: AnyObject {
    /// Production storage holds an exclusive descriptor lock for its lifetime,
    /// including the engine's capture, one owned child, and terminal commit.
    func load() throws -> PowerCommandState
    func commit(_ state: PowerCommandState) throws
}

enum PowerCommandError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

enum PowerCommandWire {
    static let maximumInputBytes = 4_096
    static let maximumReplyBytes = 16_384
    static let maximumReasonBytes = 512
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func decode(verb: String, data: Data) throws -> PowerCommandInput {
        guard let verb = PowerCommandVerb(rawValue: verb), data.count <= maximumInputBytes else {
            throw PowerCommandError.invalid("Unknown command verb or oversized input.")
        }
        if verb == .version, data.isEmpty { return .version }
        var parser = FlatObjectParser(bytes: Array(data))
        let fields = try parser.parse()
        let versionKeys: Set<String> = ["schema", "protocol"]
        let tokenKeys = versionKeys.union(["grantEpoch", "sequence", "requestID"])
        let requestKeys = tokenKeys.union(["operationID", "bootID", "profile", "key", "expectedValue", "target"])
        let sleepKeys = tokenKeys.union(["operationID", "bootID", "expiresAtContinuousTicks"])
        let required: Set<String>
        switch verb {
        case .version: required = versionKeys
        case .write, .seal: required = requestKeys
        case .sleep, .sealSleep: required = sleepKeys
        case .status, .ack: required = tokenKeys
        }
        guard Set(fields.keys) == required,
              fields["schema"] == .integer("1"), fields["protocol"] == .integer("1") else {
            throw PowerCommandError.invalid("Command keys or protocol version are invalid.")
        }
        if verb == .version { return .version }
        func string(_ name: String) throws -> String {
            guard case .string(let value) = fields[name] else { throw PowerCommandError.invalid("Expected a string field.") }
            return value
        }
        func uuid(_ name: String) throws -> UUID {
            let value = try string(name)
            guard let uuid = UUID(uuidString: value), uuid.uuidString.lowercased() == value.lowercased() else {
                throw PowerCommandError.invalid("Invalid UUID field.")
            }
            return uuid
        }
        guard case .integer(let number) = fields["sequence"], let sequence = UInt64(number) else {
            throw PowerCommandError.invalid("Sequence must be an unsigned 64-bit integer.")
        }
        let token = try PowerCommandToken(grantEpoch: uuid("grantEpoch"), sequence: sequence, requestID: uuid("requestID"))
        try token.validate()
        if verb == .status { return .status(token) }
        if verb == .ack { return .ack(token) }
        if verb == .sleep || verb == .sealSleep {
            guard case .integer(let expiryText) = fields["expiresAtContinuousTicks"],
                  let expiry = UInt64(expiryText) else {
                throw PowerCommandError.invalid("Sleep expiry must be an unsigned 64-bit integer.")
            }
            let request = try PowerSleepRequest(grantEpoch: token.grantEpoch, sequence: token.sequence,
                requestID: token.requestID, operationID: uuid("operationID"), bootID: uuid("bootID"),
                expiresAtContinuousTicks: expiry)
            try request.validate()
            return verb == .sleep ? .sleep(request) : .sealSleep(request)
        }
        guard let profile = PowerProfile(rawValue: try string("profile")), let key = ManagedKey(rawValue: try string("key")),
              case .integer(let expected) = fields["expectedValue"], let expectedValue = Int(expected),
              case .integer(let destination) = fields["target"], let target = Int(destination) else {
            throw PowerCommandError.invalid("Invalid profile, key or setting value.")
        }
        let request = try PowerCommandRequest(grantEpoch: token.grantEpoch, sequence: token.sequence,
            requestID: token.requestID, operationID: uuid("operationID"), bootID: uuid("bootID"),
            profile: profile, key: key, expectedValue: expectedValue, target: target)
        try request.validate()
        return verb == .write ? .write(request) : .seal(request)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumReplyBytes else { throw PowerCommandError.invalid("Command reply exceeds its limit.") }
        return data
    }

    static func validateReason(_ reason: String) throws {
        guard !reason.isEmpty, reason.utf8.count <= maximumReasonBytes, !reason.utf8.contains(0) else {
            throw PowerCommandError.invalid("Invalid command outcome detail.")
        }
    }

    static func reason(_ text: String) -> String {
        var bytes = Array(text.replacingOccurrences(of: "\0", with: "").utf8.prefix(maximumReasonBytes))
        while !bytes.isEmpty {
            if let value = String(bytes: bytes, encoding: .utf8) { return value }
            bytes.removeLast()
        }
        return "The command could not be completed."
    }

    /// JSONDecoder/JSONSerialization accept duplicate object keys. Scan the
    /// tiny flat wire grammar ourselves, then use JSONDecoder only for quoted
    /// string escapes and UTF-8 validation. No nested values, bools, nulls,
    /// decimal/exponent numbers, trailing data or duplicate decoded keys pass.
    private struct FlatObjectParser {
        enum Value: Equatable { case string(String), integer(String) }
        let bytes: [UInt8]
        var offset = 0
        var invalid: PowerCommandError { .invalid("Malformed flat command JSON.") }

        mutating func parse() throws -> [String: Value] {
            guard !bytes.isEmpty, !bytes.contains(0) else { throw invalid }
            whitespace()
            try consume(123)
            whitespace()
            var fields: [String: Value] = [:]
            if peek == 125 { offset += 1 } else {
                while true {
                    let key = try string()
                    guard fields[key] == nil else { throw invalid }
                    whitespace(); try consume(58); whitespace()
                    if peek == 34 { fields[key] = .string(try string()) }
                    else { fields[key] = .integer(try integer()) }
                    whitespace()
                    if peek == 125 { offset += 1; break }
                    try consume(44); whitespace()
                }
            }
            whitespace()
            guard offset == bytes.count else { throw invalid }
            return fields
        }

        var peek: UInt8? { offset < bytes.count ? bytes[offset] : nil }
        mutating func whitespace() { while let byte = peek, [9, 10, 13, 32].contains(byte) { offset += 1 } }
        mutating func consume(_ byte: UInt8) throws { guard peek == byte else { throw invalid }; offset += 1 }
        mutating func string() throws -> String {
            let start = offset
            try consume(34)
            var escaped = false
            while let byte = peek {
                offset += 1
                if byte == 34 && !escaped {
                    let value = try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset]))
                    guard !value.utf8.contains(0) else { throw invalid }
                    return value
                }
                if escaped { escaped = false } else if byte == 92 { escaped = true }
            }
            throw invalid
        }
        mutating func integer() throws -> String {
            let start = offset
            if peek == 45 { offset += 1 }
            guard let first = peek, (48...57).contains(first) else { throw invalid }
            offset += 1
            if first != 48 { while let byte = peek, (48...57).contains(byte) { offset += 1 } }
            let value = String(decoding: bytes[start..<offset], as: UTF8.self)
            guard value != "-0" else { throw invalid }
            return value
        }
    }
}
