//
//  TFYSwiftDBEncryption.swift
//  TFYSwiftSQLiteKit
//
//  Created by 田风有 on 2021/5/9.
//

import Foundation

/// Opaque key material. Descriptions and reflection always redact its bytes.
/// Store persistent secrets in the app's Keychain, not in source, UserDefaults, or database files.
public struct TFYSwiftDBKey: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let bytes: Data

    public init(passphrase: String) throws {
        try self.init(bytes: Data(passphrase.utf8))
    }

    /// Binary passphrase bytes passed unchanged to sqlite3_key (PBKDF2 still applies).
    public init(bytes: Data) throws {
        guard !bytes.isEmpty, bytes.count <= Int(Int32.max) else {
            throw TFYSwiftDBError.encryption("Key must contain between 1 and Int32.max bytes.")
        }
        self.bytes = bytes
    }

    /// SQLCipher raw key semantics: exactly 32 random bytes, optionally followed by a 16-byte salt.
    public init(rawKey: Data, salt: Data? = nil) throws {
        guard rawKey.count == 32, salt == nil || salt?.count == 16 else {
            throw TFYSwiftDBError.encryption("Raw keys require 32 bytes and an optional 16-byte salt.")
        }
        let hex = (rawKey + (salt ?? Data())).map { String(format: "%02x", $0) }.joined()
        try self.init(bytes: Data("x'\(hex)'".utf8))
    }

    public var description: String { "TFYSwiftDBKey(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["key": "<redacted>"]) }

    func withBytes<T>(_ work: (UnsafeRawPointer?, Int32) throws -> T) rethrows -> T {
        try bytes.withUnsafeBytes { try work($0.baseAddress, Int32($0.count)) }
    }

    // Internal export binding; caller must bypass SQL logging, including .full.
    var exportBinding: TFYSQLiteBindValue { .blob(bytes) }
}

public struct TFYSwiftDBEncryption: Equatable, Sendable {
    public enum Compatibility: Int, Sendable {
        case version3 = 3
        case version4 = 4
    }

    public let key: TFYSwiftDBKey
    public let compatibility: Compatibility

    public init(key: TFYSwiftDBKey, compatibility: Compatibility = .version4) {
        self.key = key
        self.compatibility = compatibility
    }
}
