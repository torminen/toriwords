import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Raw SHA-256 digest (PKCE challenge, sign-in nonces).
public func sha256(_ data: some DataProtocol) -> [UInt8] { Array(SHA256.hash(data: data)) }

/// Lowercase hex SHA-256 (dictionary install check).
public func sha256Hex(_ data: some DataProtocol) -> String { hex(sha256(data)) }

/// Lowercase hex SHA-256 of a file, read in 1 MiB chunks (the dictionary is ~60 MB; install check).
public func sha256Hex(contentsOf url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hex(hasher.finalize())
}

private func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
