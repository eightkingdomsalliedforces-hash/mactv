import CryptoKit
import Foundation

public enum PortableAppPackageError: Error, Equatable, LocalizedError, Sendable {
    case invalidPackage
    case invalidManifest(String)
    case invalidPublicKey
    case invalidSignature
    case untrustedDeveloper(String)
    case developerKeyChanged

    public var errorDescription: String? {
        switch self {
        case .invalidPackage: "不是有效的 .tvshellapp 應用套件。"
        case let .invalidManifest(reason): "App manifest 無效：\(reason)"
        case .invalidPublicKey: "開發者 Ed25519 公鑰無效。"
        case .invalidSignature: "App 簽章驗證失敗，檔案可能已遭竄改。"
        case let .untrustedDeveloper(fingerprint): "尚未信任此開發者：\(fingerprint)"
        case .developerKeyChanged: "更新套件的開發者公鑰與已安裝版本不符。"
        }
    }
}

public struct PortableAppManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var identifier: String
    public var name: String
    public var version: String
    public var entrypoint: URL
    public var allowedHosts: [String]
    public var runtime: PortableAppRuntimeKind?
    public var page: PortableDeclarativePage?

    public init(
        schemaVersion: Int = 1,
        identifier: String,
        name: String,
        version: String,
        entrypoint: URL,
        allowedHosts: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.name = name
        self.version = version
        self.entrypoint = entrypoint
        self.allowedHosts = allowedHosts
        runtime = .web
        page = nil
    }

    public init(
        schemaVersion: Int = 2,
        identifier: String,
        name: String,
        version: String,
        page: PortableDeclarativePage,
        allowedHosts: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.identifier = identifier
        self.name = name
        self.version = version
        entrypoint = URL(string: "https://declarative.invalid/")!
        self.allowedHosts = allowedHosts
        runtime = .declarative
        self.page = page
    }

    public func validate() throws {
        guard schemaVersion == 1 || schemaVersion == 2 else {
            throw PortableAppPackageError.invalidManifest("不支援 schemaVersion \(schemaVersion)")
        }
        guard identifier.range(of: #"^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+$"#, options: .regularExpression) != nil else {
            throw PortableAppPackageError.invalidManifest("identifier 必須是反向網域格式")
        }
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw PortableAppPackageError.invalidManifest("name 與 version 不可留空")
        }
        let normalizedHosts = allowedHosts.map { $0.lowercased() }
        guard normalizedHosts.allSatisfy(Self.isValidHost) else {
            throw PortableAppPackageError.invalidManifest("allowedHosts 不可使用萬用字元")
        }
        switch runtime ?? .web {
        case .web:
            guard entrypoint.scheme?.lowercased() == "https",
                  let entryHost = entrypoint.host?.lowercased(),
                  normalizedHosts.isEmpty == false,
                  normalizedHosts.contains(entryHost)
            else {
                throw PortableAppPackageError.invalidManifest("web runtime 的 entrypoint 必須是 allowedHosts 內的 HTTPS 網址")
            }
        case .declarative:
            guard schemaVersion >= 2, let page else {
                throw PortableAppPackageError.invalidManifest("declarative runtime 需要 schemaVersion 2 與 page")
            }
            try page.validate(allowedHosts: normalizedHosts)
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, identifier, name, version, entrypoint, allowedHosts, runtime, page
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        identifier = try container.decode(String.self, forKey: .identifier)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        runtime = try container.decodeIfPresent(PortableAppRuntimeKind.self, forKey: .runtime)
        page = try container.decodeIfPresent(PortableDeclarativePage.self, forKey: .page)
        entrypoint = try container.decodeIfPresent(URL.self, forKey: .entrypoint)
            ?? URL(string: "https://declarative.invalid/")!
        allowedHosts = try container.decodeIfPresent([String].self, forKey: .allowedHosts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(runtime ?? .web, forKey: .runtime)
        if (runtime ?? .web) == .web {
            try container.encode(entrypoint, forKey: .entrypoint)
        }
        if allowedHosts.isEmpty == false {
            try container.encode(allowedHosts, forKey: .allowedHosts)
        }
        try container.encodeIfPresent(page, forKey: .page)
    }

    private static func isValidHost(_ host: String) -> Bool {
        host.contains("*") == false
            && host.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$"#, options: .regularExpression) != nil
    }
}

public struct VerifiedPortableApp: Equatable, Sendable {
    public var packageURL: URL
    public var manifest: PortableAppManifest
    public var developerFingerprint: String
}

public enum PortableAppPackage {
    public static func inspect(at packageURL: URL) throws -> VerifiedPortableApp {
        guard packageURL.pathExtension.lowercased() == "tvshellapp",
              (try? packageURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { throw PortableAppPackageError.invalidPackage }

        let manifestData = try requiredData("manifest.json", in: packageURL)
        let publicKeyData = try requiredData("public-key.ed25519", in: packageURL)
        let signature = try requiredData("signature.ed25519", in: packageURL)
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        } catch {
            throw PortableAppPackageError.invalidPublicKey
        }
        guard publicKey.isValidSignature(signature, for: manifestData) else {
            throw PortableAppPackageError.invalidSignature
        }
        let manifest: PortableAppManifest
        do {
            manifest = try JSONDecoder().decode(PortableAppManifest.self, from: manifestData)
            try manifest.validate()
        } catch let error as PortableAppPackageError {
            throw error
        } catch {
            throw PortableAppPackageError.invalidManifest(error.localizedDescription)
        }
        let fingerprint = SHA256.hash(data: publicKeyData).map { String(format: "%02x", $0) }.joined()
        return VerifiedPortableApp(packageURL: packageURL, manifest: manifest, developerFingerprint: fingerprint)
    }

    private static func requiredData(_ name: String, in directory: URL) throws -> Data {
        do { return try Data(contentsOf: directory.appendingPathComponent(name)) }
        catch { throw PortableAppPackageError.invalidPackage }
    }
}

public struct PortableAppInstaller: Sendable {
    public var installedAppsDirectory: URL
    public var trustStoreURL: URL

    public init(installedAppsDirectory: URL, trustStoreURL: URL) {
        self.installedAppsDirectory = installedAppsDirectory
        self.trustStoreURL = trustStoreURL
    }

    public static func applicationSupport() -> PortableAppInstaller {
        let root = TVShellStorageMigration.resolvedApplicationSupportDirectory()
        return PortableAppInstaller(
            installedAppsDirectory: root.appendingPathComponent("Apps", isDirectory: true),
            trustStoreURL: root.appendingPathComponent("trusted-apps.json")
        )
    }

    public func install(_ package: VerifiedPortableApp, trustingNewDeveloper: Bool) throws -> TVAppProfile {
        var trust = try loadTrust()
        if let existingFingerprint = trust[package.manifest.identifier],
           existingFingerprint != package.developerFingerprint {
            throw PortableAppPackageError.developerKeyChanged
        }
        if trust[package.manifest.identifier] == nil {
            guard trustingNewDeveloper else {
                throw PortableAppPackageError.untrustedDeveloper(package.developerFingerprint)
            }
            trust[package.manifest.identifier] = package.developerFingerprint
        }

        try FileManager.default.createDirectory(at: installedAppsDirectory, withIntermediateDirectories: true)
        let destination = installedAppsDirectory.appendingPathComponent("\(package.manifest.identifier).tvshellapp", isDirectory: true)
        let temporary = installedAppsDirectory.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: package.packageURL, to: temporary)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            try saveTrust(trust)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return Self.profile(for: package.manifest)
    }

    public func installedProfiles() throws -> [TVAppProfile] {
        let trust = try loadTrust()
        guard FileManager.default.fileExists(atPath: installedAppsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: installedAppsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "tvshellapp" }
        .compactMap { url -> TVAppProfile? in
            guard let package = try? PortableAppPackage.inspect(at: url),
                  trust[package.manifest.identifier] == package.developerFingerprint
            else { return nil }
            return Self.profile(for: package.manifest)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func uninstall(identifier: String) throws {
        let destination = installedAppsDirectory.appendingPathComponent("\(identifier).tvshellapp", isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        var trust = try loadTrust()
        trust.removeValue(forKey: identifier)
        try saveTrust(trust)
    }

    public func identifier(forInstalledAppID appID: UUID) throws -> String? {
        guard FileManager.default.fileExists(atPath: installedAppsDirectory.path) else { return nil }
        return try FileManager.default.contentsOfDirectory(
            at: installedAppsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .compactMap { try? PortableAppPackage.inspect(at: $0).manifest }
        .first { Self.profile(for: $0).id == appID }?
        .identifier
    }

    private func loadTrust() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: trustStoreURL.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: trustStoreURL))
    }

    private func saveTrust(_ trust: [String: String]) throws {
        try FileManager.default.createDirectory(at: trustStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(trust).write(to: trustStoreURL, options: .atomic)
    }

    private static func profile(for manifest: PortableAppManifest) -> TVAppProfile {
        let target: LaunchTarget
        let controlMode: ControlMode
        if (manifest.runtime ?? .web) == .declarative, let page = manifest.page {
            target = .portableDeclarative(page: page, allowedHosts: manifest.allowedHosts)
            controlMode = .nativeKeyboard
        } else {
            target = .portableWeb(entrypoint: manifest.entrypoint, allowedHosts: manifest.allowedHosts)
            controlMode = .web
        }
        return TVAppProfile(
            id: stableUUID(for: manifest.identifier),
            name: manifest.name,
            target: target,
            controlMode: controlMode
        )
    }

    private static func stableUUID(for value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
