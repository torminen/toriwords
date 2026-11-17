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

/// Raw SHA-256 digest (PKCE challenge, sign-in nonces).
public func sha256(_ data: some DataProtocol) -> [UInt8] { Array(SHA256.hash(data: data)) }
