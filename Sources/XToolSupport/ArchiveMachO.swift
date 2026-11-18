import Foundation
import Crypto
import XCLIUtils

struct ArchiveMachO {
    struct Slice {
        let cpu: UInt32
        let platform: UInt32
        let minimum: UInt32
        let sdk: UInt32
        let codeDirectory: Data?
        let signature: Data?
    }
    let slices: [Slice]

    init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        let magic = try Self.uint32(data, 0)
        if magic == 0xbebafeca || magic == 0xbfbafeca {
            let count = Int(try Self.uint32(data, 4).byteSwapped)
            guard count > 0 && count <= 16 else { throw Self.invalid() }
            let stride = magic == 0xbebafeca ? 20 : 32
            slices = try (0..<count).map { index in
                let entry = 8 + index * stride
                guard magic == 0xbebafeca else {
                    throw Console.Error("64-bit fat Mach-O containers are not supported by archive validation.")
                }
                let offset = Int(try Self.uint32(data, entry + 8).byteSwapped)
                let length = Int(try Self.uint32(data, entry + 12).byteSwapped)
                return try Self.parse(data: Self.bytes(data, offset, length))
            }
        } else {
            slices = [try Self.parse(data: data)]
        }
    }

    static func version(_ string: String) throws -> UInt32 {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { throw invalid() }
        let numbers = parts.compactMap { UInt32($0) }
        guard numbers.count == parts.count, numbers[0] <= 65535,
              numbers.dropFirst().allSatisfy({ $0 <= 255 }) else { throw invalid() }
        return numbers[0] << 16 | (numbers.count > 1 ? numbers[1] << 8 : 0) | (numbers.count > 2 ? numbers[2] : 0)
    }

    func validate(platform: String, minimum: String, sdk: String) throws {
        let expectedPlatform: UInt32 = platform == "watchos" ? 4 : 2
        let cpus = try Self.requiredCPUs(platform: platform, minimum: minimum)
        guard Set(slices.map(\.cpu)) == cpus else {
            throw Console.Error("Distribution binaries must contain every required device architecture.")
        }
        for slice in slices {
            guard slice.platform == expectedPlatform,
                  slice.minimum == (try Self.version(minimum)), slice.sdk == (try Self.version(sdk)) else {
                throw Console.Error("Mach-O architecture, platform, minimum OS or SDK does not match the bundle metadata.")
            }
        }
    }

    static func requiredCPUs(platform: String, minimum: String) throws -> Set<UInt32> {
        if platform == "watchos", try version(minimum) < 27 << 16 { return [0x0100000c, 0x0200000c] }
        return [0x0100000c]
    }

    private static func parse(data: Data) throws -> Slice {
        let magic = try uint32(data, 0)
        guard magic == 0xfeedfacf || magic == 0xfeedface else { throw invalid() }
        let cpu = try uint32(data, 4)
        let count = Int(try uint32(data, 16))
        let header = magic == 0xfeedfacf ? 32 : 28
        let end = header + Int(try uint32(data, 20))
        guard count <= 4096, end <= data.count else { throw invalid() }
        var position = header
        var build: (UInt32, UInt32, UInt32)?
        var signature: Data?
        var directory: Data?
        for _ in 0..<count {
            let command = try uint32(data, position)
            let length = Int(try uint32(data, position + 4))
            guard length >= 8, position + length <= end else { throw invalid() }
            if command == 0x32 {
                guard length >= 24 else { throw invalid() }
                build = try (uint32(data, position + 8), uint32(data, position + 12), uint32(data, position + 16))
            }
            if command == 0x1d {
                guard length >= 16 else { throw invalid() }
                let offset = Int(try uint32(data, position + 8))
                let size = Int(try uint32(data, position + 12))
                (directory, signature) = try signatureParts(bytes(data, offset, size))
                if let directory { try validateCodeHashes(directory, executable: data) }
            }
            position += length
        }
        guard position == end, let build else { throw invalid() }
        return Slice(cpu: cpu, platform: build.0, minimum: build.1, sdk: build.2,
                     codeDirectory: directory, signature: signature)
    }

    private static func signatureParts(_ data: Data) throws -> (Data?, Data?) {
        guard try uint32(data, 0).byteSwapped == 0xfade0cc0 else { throw invalid() }
        let count = Int(try uint32(data, 8).byteSwapped)
        guard count <= 64 else { throw invalid() }
        var directory: Data?
        var signature: Data?
        for index in 0..<count {
            let type = try uint32(data, 12 + index * 8).byteSwapped
            let offset = Int(try uint32(data, 16 + index * 8).byteSwapped)
            let length = Int(try uint32(data, offset + 4).byteSwapped)
            if type == 0 { directory = try bytes(data, offset, length) }
            if type == 0x10000 { signature = try bytes(data, offset + 8, length - 8) }
        }
        return (directory, signature)
    }

    private static func uint32(_ data: Data, _ offset: Int) throws -> UInt32 {
        let bytes = try bytes(data, offset, 4)
        return bytes.enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) }
    }

    private static func validateCodeHashes(_ directory: Data, executable: Data) throws {
        guard try uint32(directory, 0).byteSwapped == 0xfade0c02 else { throw invalid() }
        let hashOffset = Int(try uint32(directory, 16).byteSwapped)
        let count = Int(try uint32(directory, 28).byteSwapped)
        let limit = Int(try uint32(directory, 32).byteSwapped)
        let parameters = try bytes(directory, 36, 4)
        let size = Int(parameters[0])
        let type = parameters[1]
        let exponent = Int(parameters[3])
        guard exponent <= 20, size > 0, limit <= executable.count else { throw invalid() }
        let page = exponent == 0 ? max(limit, 1) : 1 << exponent
        guard count == (limit + page - 1) / page else { throw invalid() }
        for index in 0..<count {
            let data = try bytes(executable, index * page, min(page, limit - index * page))
            let digest = try hash(data, type: type)
            guard size <= digest.count, try bytes(directory, hashOffset + index * size, size) == digest.prefix(size) else {
                throw Console.Error("Executable code does not match its signature hashes.")
            }
        }
    }

    func validateBundleSeals(info: Data, resources: Data) throws {
        for slice in slices {
            guard let directory = slice.codeDirectory else { throw Self.invalid() }
            let hashOffset = Int(try Self.uint32(directory, 16).byteSwapped)
            let slots = Int(try Self.uint32(directory, 24).byteSwapped)
            let parameters = try Self.bytes(directory, 36, 2)
            let size = Int(parameters[0])
            guard slots >= 3, size > 0 else { throw Self.invalid() }
            for (slot, data) in [(1, info), (3, resources)] {
                let expected = try Self.bytes(directory, hashOffset - slot * size, size)
                let actual = try Self.hash(data, type: parameters[1])
                guard size <= actual.count, expected == actual.prefix(size) else {
                    throw Console.Error("Info.plist or resource seal does not match the executable signature.")
                }
            }
        }
    }

    private static func hash(_ data: Data, type: UInt8) throws -> Data {
        switch type {
        case 1: Data(Insecure.SHA1.hash(data: data))
        case 2, 3: Data(SHA256.hash(data: data))
        default: throw invalid()
        }
    }

    private static func bytes(_ data: Data, _ offset: Int, _ count: Int) throws -> Data {
        guard offset >= 0, count >= 0, offset <= data.count, count <= data.count - offset else { throw invalid() }
        return data.subdata(in: offset..<(offset + count))
    }

    private static func invalid() -> Console.Error { Console.Error("Invalid or unsupported Mach-O in distribution archive.") }
}
