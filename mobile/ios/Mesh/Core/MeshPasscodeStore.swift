import CryptoKit
import Foundation
import Security

enum MeshPasscodeStore {
    private static let enabledKey = "mesh.passcode.enabled"
    private static let biometricKey = "mesh.passcode.biometric"
    private static let hashAccount = "mesh.passcode.hash"
    private static let saltAccount = "mesh.passcode.salt"

    static let digitCount = 6

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey) && loadHash() != nil
    }

    static var isBiometricEnabled: Bool {
        UserDefaults.standard.bool(forKey: biometricKey) && isEnabled
    }

    static func setPasscode(_ passcode: String) -> Bool {
        guard passcode.count == digitCount, passcode.allSatisfy(\.isNumber) else { return false }

        let salt = randomSalt()
        let hash = hash(passcode: passcode, salt: salt)
        guard KeychainService.save(hash, account: hashAccount),
              KeychainService.save(salt, account: saltAccount)
        else { return false }

        UserDefaults.standard.set(true, forKey: enabledKey)
        return true
    }

    static func verify(_ passcode: String) -> Bool {
        guard passcode.count == digitCount,
              let storedHash = loadHash(),
              let salt = loadSalt()
        else { return false }
        return hash(passcode: passcode, salt: salt) == storedHash
    }

    static func setBiometricEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: biometricKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: biometricKey)
        _ = KeychainService.delete(account: hashAccount)
        _ = KeychainService.delete(account: saltAccount)
    }

    private static func loadHash() -> Data? {
        KeychainService.load(account: hashAccount)
    }

    private static func loadSalt() -> Data? {
        KeychainService.load(account: saltAccount)
    }

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func hash(passcode: String, salt: Data) -> Data {
        var combined = salt
        combined.append(contentsOf: Data(passcode.utf8))
        return Data(SHA256.hash(data: combined))
    }
}

private extension Character {
    var isNumber: Bool { isWholeNumber }
}
