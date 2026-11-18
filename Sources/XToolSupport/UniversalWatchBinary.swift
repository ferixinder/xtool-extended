import Foundation
import XCLIUtils

enum UniversalWatchBinary {
    static func merge(_ first: URL, _ second: URL, into destination: URL) throws {
        let inputs = try [first, second].map { url -> (URL, UInt32, UInt32, UInt32) in
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let size = try file.seekToEnd()
            try file.seek(toOffset: 0)
            guard let header = try file.read(upToCount: 12), header.count == 12,
                  size <= UInt32.max else { throw error() }
            func word(_ offset: Int) -> UInt32 {
                header[offset..<(offset + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) }
            }
            guard word(0) == 0xfeedfacf || word(0) == 0xfeedface else { throw error() }
            return (url, word(4), word(8), UInt32(size))
        }
        guard Set(inputs.map(\.1)) == [0x0100000c, 0x0200000c] else { throw error() }
        let alignment: UInt64 = 1 << 14
        var cursor = alignment
        var header = Data()
        func append(_ value: UInt32) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { header.append(contentsOf: $0) }
        }
        append(0xcafebabe)
        append(2)
        var offsets: [UInt64] = []
        for (_, cpu, subtype, size) in inputs {
            guard cursor + UInt64(size) <= UInt32.max else { throw error() }
            offsets.append(cursor)
            append(cpu)
            append(subtype)
            append(UInt32(cursor))
            append(size)
            append(14)
            cursor = (cursor + UInt64(size) + alignment - 1) & ~(alignment - 1)
        }
        try header.write(to: destination, options: .withoutOverwriting)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for (index, input) in inputs.enumerated() {
            try output.seek(toOffset: offsets[index])
            let source = try FileHandle(forReadingFrom: input.0)
            defer { try? source.close() }
            while let bytes = try source.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: bytes)
            }
        }
    }

    private static func error() -> Console.Error { Console.Error("Cannot create universal Watch binary from these slices.") }
}
