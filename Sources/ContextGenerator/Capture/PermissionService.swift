import ApplicationServices
import CoreGraphics
import Foundation

public protocol PermissionServicing {
    func requestOnboardingPermissions()
    func hasAccessibilityPermission() -> Bool
    func hasScreenRecordingPermission() -> Bool
}

public final class PermissionService: PermissionServicing {
    public init() {}

    public func requestOnboardingPermissions() {
        let accessibilityOptions = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(accessibilityOptions)

        if #available(macOS 10.15, *) {
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
        }
    }

    public func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    public func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }

        return true
    }
}
