import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Lowercase hex SHA-256 (dictionary install check, doc 36 §8.3).
public func sha256Hex(_ data: some DataProtocol) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// Lowercase hex SHA-256 of a file, read in 1 MiB chunks (the dictionary is ~60 MB; §8.3 install check).
public func sha256Hex(contentsOf url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}
