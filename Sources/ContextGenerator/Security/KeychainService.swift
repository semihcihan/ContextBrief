import Foundation
import Security

public protocol KeychainServicing {
    func set(_ value: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func delete(_ key: String) throws
}

public final class KeychainService: KeychainServicing {
    private let service = "ContextBrief"

    public init() {}

    public func set(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
            return
        }

        if updateStatus != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }
    }

    public func get(_ key: String) throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    public func delete(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
