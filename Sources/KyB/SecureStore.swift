import CommonCrypto
import CryptoKit
import Darwin
import Foundation
import Security

struct VaultFile: Codable {
    var version: Int = 1
    var salt: Data
    var nonce: Data
    var ciphertext: Data
    var tag: Data
    var kdfIterations: UInt32? = nil
}

struct VaultPayload: Codable {
    var mappings: [Mapping]
    var settings: VaultSettings?
}

struct VaultSession {
    let salt: Data
    let key: SymmetricKey
    let kdfIterations: UInt32
}

enum SecureStoreError: LocalizedError {
    case badPassword
    case cryptoFailed
    case missingSession
    case invalidVault
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .badPassword: "Bad password or corrupt vault"
        case .cryptoFailed: "Crypto operation failed"
        case .missingSession: "Vault not unlocked"
        case .invalidVault: "Invalid or unsupported vault file"
        case .unsafePath: "Unsafe vault path"
        }
    }
}

final class SecureStore {
    private static let legacyIterations: UInt32 = 210_000
    private static let currentIterations: UInt32 = 600_000
    private static let maxVaultBytes = 2 * 1024 * 1024

    private let fileURL: URL

    init() throws {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("KyB", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = chmod(dir.path, S_IRWXU)
        fileURL = dir.appendingPathComponent("vault.json")
        try rejectSymlinkIfPresent(fileURL)
        hardenVaultPermissionsIfPresent()
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    var path: String {
        fileURL.path
    }

    func unlock(password: String) throws -> (mappings: [Mapping], settings: VaultSettings, session: VaultSession) {
        try rejectSymlinkIfPresent(fileURL)
        let vault = try readVault(from: fileURL)
        let iterations = vault.kdfIterations ?? Self.legacyIterations
        let key = try deriveKey(password: password, salt: vault.salt, iterations: iterations)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: vault.nonce), ciphertext: vault.ciphertext, tag: vault.tag)
        do {
            let opened = try AES.GCM.open(box, using: key)
            let payload = try JSONDecoder().decode(VaultPayload.self, from: opened)
            let mappings = payload.mappings
            let settings = payload.settings ?? VaultSettings()
            hardenVaultPermissionsIfPresent()
            return (mappings, settings, VaultSession(salt: vault.salt, key: key, kdfIterations: iterations))
        } catch {
            throw SecureStoreError.badPassword
        }
    }

    func create(password: String, mappings: [Mapping], settings: VaultSettings) throws -> VaultSession {
        let salt = try randomData(count: 32)
        let key = try deriveKey(password: password, salt: salt, iterations: Self.currentIterations)
        let session = VaultSession(salt: salt, key: key, kdfIterations: Self.currentIterations)
        try save(mappings: mappings, settings: settings, session: session)
        return session
    }

    func save(mappings: [Mapping], settings: VaultSettings, session: VaultSession) throws {
        try rejectSymlinkIfPresent(fileURL)
        let payload = try JSONEncoder().encode(VaultPayload(mappings: mappings, settings: settings))
        let box = try AES.GCM.seal(payload, using: session.key)
        let vault = VaultFile(
            salt: session.salt,
            nonce: Data(box.nonce),
            ciphertext: box.ciphertext,
            tag: box.tag,
            kdfIterations: session.kdfIterations
        )
        try validate(vault)
        let data = try JSONEncoder().encode(vault)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        hardenVaultPermissionsIfPresent()
    }

    func validateImportCandidate(_ url: URL) throws {
        _ = try readVault(from: url)
    }

    private func readVault(from url: URL) throws -> VaultFile {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber, size.intValue > Self.maxVaultBytes {
            throw SecureStoreError.invalidVault
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maxVaultBytes else { throw SecureStoreError.invalidVault }
        let vault = try JSONDecoder().decode(VaultFile.self, from: data)
        try validate(vault)
        return vault
    }

    private func validate(_ vault: VaultFile) throws {
        guard vault.version == 1 else { throw SecureStoreError.invalidVault }
        guard (16 ... 64).contains(vault.salt.count) else { throw SecureStoreError.invalidVault }
        guard vault.nonce.count == 12 else { throw SecureStoreError.invalidVault }
        guard vault.tag.count == 16 else { throw SecureStoreError.invalidVault }
        guard !vault.ciphertext.isEmpty, vault.ciphertext.count <= Self.maxVaultBytes else { throw SecureStoreError.invalidVault }
        let iterations = vault.kdfIterations ?? Self.legacyIterations
        guard iterations >= Self.legacyIterations, iterations <= 2_000_000 else { throw SecureStoreError.invalidVault }
    }

    private func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard let passwordData = password.data(using: .utf8) else { throw SecureStoreError.cryptoFailed }
        let derivedCount = 32
        var derived = Data(repeating: 0, count: derivedCount)
        let result = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedCount
                    )
                }
            }
        }
        guard result == kCCSuccess else { throw SecureStoreError.cryptoFailed }
        defer { derived.resetBytes(in: 0 ..< derived.count) }
        return SymmetricKey(data: derived)
    }

    private func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw SecureStoreError.cryptoFailed }
        return Data(bytes)
    }

    private func hardenVaultPermissionsIfPresent() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        _ = chmod(fileURL.path, S_IRUSR | S_IWUSR)
    }

    private func rejectSymlinkIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true { throw SecureStoreError.unsafePath }
    }
}
