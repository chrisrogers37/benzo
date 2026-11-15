import Foundation

/// A principal resolved from the authenticated XPC peer, never a client-supplied UID.
struct HelperOwner: Codable, Equatable {
    let uid: UInt32
    let generatedUID: UUID

    func validate() throws {
        guard uid != 0, generatedUID != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) else {
            throw HelperProtocolError.invalid("The setup account could not be identified.")
        }
    }
}

struct HelperWriteRequest: Codable, Equatable {
    var schema: Int = 1
    let requestID: UUID
    let operationID: UUID
    let bootID: String
    let cell: ManagedCell
    let expectedValue: Int
    let target: Int
    let expectedRevision: UInt64

    func validate() throws {
        guard schema == 1, UUID(uuidString: bootID)?.uuidString == bootID,
              cell.key.isValid(expectedValue), cell.key.isValid(target),
              expectedRevision < UInt64.max else {
            throw HelperProtocolError.invalid("The setting request has an unsupported identity or value.")
        }
    }
}

enum HelperWriteDisposition: Codable, Equatable {
    case completed(exitStatus: Int)
    case notExecuted(reason: String)
    case uncertain(reason: String)
}

struct HelperWriteReply: Codable, Equatable {
    var schema: Int = 1
    let request: HelperWriteRequest
    let outcome: HelperWriteDisposition
    let revision: UInt64

    func validatedOutcome(for expectedRequest: HelperWriteRequest) throws -> RecoveryWriteOutcome {
        try expectedRequest.validate()
        guard schema == 1, request == expectedRequest else {
            throw HelperProtocolError.invalid("The helper reply does not match the admitted request.")
        }
        switch outcome {
        case .completed(let status):
            guard revision == expectedRequest.expectedRevision + 1, (0...255).contains(status) else {
                throw HelperProtocolError.invalid("The helper completion revision or status is invalid.")
            }
            return .completed(status: status)
        case .notExecuted(let reason):
            guard (revision == expectedRequest.expectedRevision || revision == expectedRequest.expectedRevision + 1),
                  !reason.isEmpty, reason.utf8.count <= HelperProtocolLimits.maximumReasonBytes else {
                throw HelperProtocolError.invalid("The helper rejection does not establish this request's execution state.")
            }
            return .notExecuted(reason)
        case .uncertain(let reason):
            guard !reason.isEmpty, reason.utf8.count <= HelperProtocolLimits.maximumReasonBytes else {
                throw HelperProtocolError.invalid("The helper uncertainty response is invalid.")
            }
            return .uncertain(reason)
        }
    }
}

struct HelperExecutionFence: Codable, Equatable {
    let request: HelperWriteRequest
    var completedStatus: Int? = nil
    var notExecutedReason: String? = nil

    var isIncomplete: Bool { completedStatus == nil && notExecutedReason == nil }

    func validate() throws {
        try request.validate()
        guard !(completedStatus != nil && notExecutedReason != nil),
              completedStatus.map({ (0...255).contains($0) }) ?? true,
              notExecutedReason.map({ !$0.isEmpty && $0.utf8.count <= HelperProtocolLimits.maximumReasonBytes }) ?? true else {
            throw HelperProtocolError.invalid("The helper execution receipt is invalid.")
        }
    }
}

/// Only machine-wide ownership and execution admission live here. Original
/// settings, selected controls and recovery plans remain in the GUI journal.
struct HelperAuthorityState: Codable, Equatable {
    var schema: Int = 1
    let owner: HelperOwner
    var revision: UInt64
    var lastExecution: HelperExecutionFence?
    var priorUncertainExecution: HelperExecutionFence? = nil

    func validate() throws {
        try owner.validate()
        guard schema == 1 else { throw HelperProtocolError.invalid("Unsupported helper authority schema.") }
        if let lastExecution {
            try lastExecution.validate()
            guard revision > 0, lastExecution.request.expectedRevision == revision - 1 else {
                throw HelperProtocolError.invalid("The helper execution revision is inconsistent.")
            }
        } else if revision != 0 || priorUncertainExecution != nil {
            throw HelperProtocolError.invalid("Helper execution evidence is missing.")
        }
        if let priorUncertainExecution {
            try priorUncertainExecution.validate()
            guard priorUncertainExecution.isIncomplete,
                  priorUncertainExecution.request.expectedRevision < revision - 1,
                  priorUncertainExecution.request.requestID != lastExecution?.request.requestID else {
                throw HelperProtocolError.invalid("Prior helper uncertainty evidence is inconsistent.")
            }
        }
    }

    func blocksWrites(on bootID: String) -> Bool {
        guard let lastExecution, lastExecution.isIncomplete else { return false }
        // Retain one previous-boot uncertain request. A second cannot silently
        // replace it: administrator-assisted recovery must preserve the evidence.
        return lastExecution.request.bootID == bootID || priorUncertainExecution != nil
    }
}

struct HelperStatus: Codable, Equatable {
    var schema: Int = 1
    let owner: HelperOwner?
    let revision: UInt64
    let bootID: String
    let executionUncertain: Bool
    let buildIdentifier: String
    let replacementPrepared: Bool
}

protocol HelperAuthorityStoring: AnyObject {
    /// nil means an explicitly stored unenrolled state, never missing established evidence.
    func load() throws -> HelperAuthorityState?
    func commit(_ state: HelperAuthorityState) throws
}

enum HelperProtocolError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

enum HelperProtocolLimits {
    static let maximumPayloadBytes = 16_384
    static let maximumReasonBytes = 512

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumPayloadBytes else { throw HelperProtocolError.invalid("Helper reply exceeded its limit.") }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumPayloadBytes else {
            throw HelperProtocolError.invalid("Helper request is empty or exceeds its limit.")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    static func reason(_ text: String) -> String {
        // Keep replies and durable evidence bounded even when an injected OS
        // failure includes a long description. No command output is persisted.
        var bytes = Array(text.utf8.prefix(maximumReasonBytes))
        // A byte prefix can split only the final UTF-8 scalar. Drop its partial
        // bytes; counting Characters would not bound long combining sequences.
        while !bytes.isEmpty {
            if let bounded = String(bytes: bytes, encoding: .utf8) { return bounded }
            bytes.removeLast()
        }
        return "The helper request could not be completed."
    }
}
