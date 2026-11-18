import Foundation

public struct BuildUploadStatus: Sendable {
    public let uploadID: String
    public let state: String
    public let buildID: String?
    public let processingState: String?
    public let errors: [String]

    public var accepted: Bool { state == "COMPLETE" && processingState == "VALID" }
    public var failed: Bool { state == "FAILED" || processingState.map { ["INVALID", "FAILED"].contains($0) } == true }
}

struct UploadEnvelope<T: Decodable>: Decodable { let data: T }
struct UploadResource<A: Decodable>: Decodable {
    let id: String
    let attributes: A
    let relationships: Relationships?

    struct Relationships: Decodable {
        let build: Relationship?
        struct Relationship: Decodable {
            let data: Identifier?
            struct Identifier: Decodable { let id: String }
        }
    }
}
struct UploadApp: Decodable { let bundleId: String }
struct UploadBuild: Decodable {
    let version: String
    let processingState: String
}
struct UploadAttributes: Decodable {
    let cfBundleShortVersionString: String
    let cfBundleVersion: String
    let state: State?
    struct State: Decodable {
        let state: String
        let errors: [Detail]?
        struct Detail: Decodable {
            let code: String?
            let description: String?
        }
    }
}
struct UploadFileAttributes: Decodable {
    let uploadOperations: [BuildUploadOperation]?
}

struct UploadAPIFailure: Decodable {
    struct Detail: Decodable { let code: String?; let detail: String? }
    let errors: [Detail]
}

struct BuildUploadOperation: Decodable, Sendable {
    let method: String
    let url: String
    let length: Int64
    let offset: Int64
    let requestHeaders: [Header]?
    struct Header: Decodable, Sendable {
        let name: String
        let value: String
    }
}
