import Crypto
import Foundation
import OpenAPIRuntime

struct BuildUploadFile {
    let url: URL
    let size: Int64
    let md5: String

    init(url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = Insecure.MD5()
        var size: Int64 = 0
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
            size += Int64(data.count)
        }
        guard size > 0 else { throw BuildUploader.Error.invalidFile }
        self.url = url
        self.size = size
        self.md5 = hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func validate(_ operations: [BuildUploadOperation]) throws {
        var end: Int64 = 0
        for operation in operations.sorted(by: { $0.offset < $1.offset }) {
            guard operation.offset == end, operation.length > 0, operation.length <= size - end,
                  operation.method == "PUT", let url = URL(string: operation.url),
                  url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  url.fragment == nil, url.port == nil || url.port == 443 else {
                throw BuildUploader.Error.invalidOperations
            }
            end += operation.length
        }
        guard end == size else { throw BuildUploader.Error.invalidOperations }
    }

    func body(offset: Int64, length: Int64) throws -> HTTPBody {
        guard offset >= 0, offset <= size, length > 0, length <= size - offset else {
            throw BuildUploader.Error.invalidOperations
        }
        let reader = try Reader(url: url, offset: offset, length: length)
        let chunks = AsyncThrowingStream<HTTPBody.ByteChunk, any Swift.Error>(unfolding: { try await reader.next() })
        return HTTPBody(chunks, length: .known(length), iterationBehavior: .single)
    }

    private actor Reader {
        let file: FileHandle
        var remaining: Int64

        init(url: URL, offset: Int64, length: Int64) throws {
            file = try FileHandle(forReadingFrom: url)
            try file.seek(toOffset: UInt64(offset))
            remaining = length
        }

        deinit { try? file.close() }

        func next() throws -> HTTPBody.ByteChunk? {
            try Task.checkCancellation()
            guard remaining > 0 else { return nil }
            guard let data = try file.read(upToCount: Int(min(remaining, 1024 * 1024))), !data.isEmpty else {
                throw BuildUploader.Error.invalidFile
            }
            remaining -= Int64(data.count)
            return Array(data)[...]
        }
    }
}
