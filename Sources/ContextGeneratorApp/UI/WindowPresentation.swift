import AppKit

extension NSWindowController {
    func presentWindowAsFrontmost(_ sender: Any?) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        window?.orderFrontRegardless()
    }
}
