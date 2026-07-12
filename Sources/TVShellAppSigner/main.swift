import CryptoKit
import Foundation

enum SignerError: Error, LocalizedError {
    case usage
    case outputExists

    var errorDescription: String? {
        switch self {
        case .usage:
            "用法：\n  TVShellAppSigner generate-key <private-key>\n  TVShellAppSigner sign <manifest.json> <private-key> <output.tvshellapp>"
        case .outputExists:
            "輸出套件已存在；請先選擇新的路徑。"
        }
    }
}

@main
struct TVShellAppSigner {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { throw SignerError.usage }
        let operands = Array(arguments.dropFirst())
        if command == "generate-key", operands.count == 1 {
            let keyPath = operands[0]
            let key = Curve25519.Signing.PrivateKey()
            try key.rawRepresentation.write(to: URL(fileURLWithPath: keyPath), options: [.atomic, .withoutOverwriting])
            print("已建立 Ed25519 私鑰：\(keyPath)")
            print("公鑰指紋：\(fingerprint(key.publicKey.rawRepresentation))")
        } else if command == "sign", operands.count == 3 {
            let manifestPath = operands[0]
            let keyPath = operands[1]
            let outputPath = operands[2]
            let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
            guard outputURL.pathExtension.lowercased() == "tvshellapp" else { throw SignerError.usage }
            guard FileManager.default.fileExists(atPath: outputURL.path) == false else { throw SignerError.outputExists }
            let manifestData = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
            let privateKey = try Curve25519.Signing.PrivateKey(
                rawRepresentation: Data(contentsOf: URL(fileURLWithPath: keyPath))
            )
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            do {
                try manifestData.write(to: outputURL.appendingPathComponent("manifest.json"))
                try privateKey.publicKey.rawRepresentation.write(to: outputURL.appendingPathComponent("public-key.ed25519"))
                try privateKey.signature(for: manifestData).write(to: outputURL.appendingPathComponent("signature.ed25519"))
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
            print("已簽署：\(outputURL.path)")
            print("開發者指紋：\(fingerprint(privateKey.publicKey.rawRepresentation))")
        } else {
            throw SignerError.usage
        }
    }

    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
