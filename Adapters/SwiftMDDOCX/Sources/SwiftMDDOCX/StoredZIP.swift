// SPDX-License-Identifier: Apache-2.0
import Foundation

// Deliberately limited OPC ZIP writer: no compression, ZIP64, input paths or I/O.
// Independently implemented from the ZIP file format, not copied from RhoeDOCX.
enum StoredZIP {
    static func create(_ parts: [(String, Data)]) throws -> Data {
        guard let count = UInt16(exactly: parts.count) else { throw DOCXError.archiveTooLarge }
        var output = Data(), directory = Data()
        for (name, content) in parts {
            let filename = Data(name.utf8)
            guard let nameSize = UInt16(exactly: filename.count),
                  let size = UInt32(exactly: content.count),
                  let offset = UInt32(exactly: output.count) else { throw DOCXError.archiveTooLarge }
            let crc = checksum(content)
            output.le(UInt32(0x04034b50)); output.le(UInt16(20)); output.le(UInt16(0x0800))
            output.le(UInt16(0)); output.le(UInt16(0)); output.le(UInt16(0x0021))
            output.le(crc); output.le(size); output.le(size); output.le(nameSize); output.le(UInt16(0))
            output.append(filename); output.append(content)
            directory.le(UInt32(0x02014b50)); directory.le(UInt16(20)); directory.le(UInt16(20))
            directory.le(UInt16(0x0800)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0x0021))
            directory.le(crc); directory.le(size); directory.le(size); directory.le(nameSize)
            directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0))
            directory.le(UInt32(0)); directory.le(offset); directory.append(filename)
        }
        guard let directoryOffset = UInt32(exactly: output.count),
              let directorySize = UInt32(exactly: directory.count),
              UInt64(output.count) + UInt64(directory.count) + 22 <= UInt64(UInt32.max) else {
            throw DOCXError.archiveTooLarge
        }
        output.append(directory)
        output.le(UInt32(0x06054b50)); output.le(UInt16(0)); output.le(UInt16(0))
        output.le(count); output.le(count); output.le(directorySize); output.le(directoryOffset); output.le(UInt16(0))
        return output
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb8_8320 & (0 &- (crc & 1))) }
        }
        return ~crc
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ number: T) {
        var value = number.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
