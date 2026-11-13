import Foundation

/// Only bounded Foundation Data and String cross XPC. The payload is a closed,
/// versioned Codable vocabulary; no object graphs, paths or shell commands.
@objc protocol BenzoHelperXPC {
    func status(withReply reply: @escaping (Data?, String?) -> Void)
    func enroll(_ authorization: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func prepareForReplacement(withReply reply: @escaping (Data?, String?) -> Void)
    func write(_ request: Data, withReply reply: @escaping (Data?, String?) -> Void)
}

enum HelperServiceDefinition {
    static let appIdentifier = "com.benzo.app"
    static let helperIdentifier = "com.benzo.helper"
    static let machServiceName = "com.benzo.helper"
    static let plistName = "com.benzo.helper.plist"
    static let maximumPayloadBytes = 16_384

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumPayloadBytes else { throw failure("The helper message is too large.") }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw failure("The helper message size is invalid.") }
        return try JSONDecoder().decode(type, from: data)
    }

    static func failure(_ message: String) -> NSError {
        NSError(domain: "com.benzo.helper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
