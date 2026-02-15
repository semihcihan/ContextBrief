import Carbon
import ContextGenerator
import Foundation

final class GlobalHotkeyManager {
    enum Action: CaseIterable {
        case addSnapshot
        case copyCurrentContext

        var id: UInt32 {
            switch self {
            case .addSnapshot:
                return 1
            case .copyCurrentContext:
                return 2
            }
        }
    }

    private struct Constants {
        static let signature: OSType = 0x43545847
    }

    private var hotKeyRefs: [Action: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private let onTrigger: (Action) -> Void

    init(onTrigger: @escaping (Action) -> Void) {
        self.onTrigger = onTrigger
        installHandler()
    }

    deinit {
        unregisterAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func apply(shortcuts: ShortcutPreferences) -> [Action] {
        unregisterAll()
        if shortcuts.addSnapshot == shortcuts.copyCurrentContext {
            let _ = register(binding: shortcuts.addSnapshot, action: .addSnapshot)
            return [.copyCurrentContext]
        }
        var failed: [Action] = []
        let ordered: [(Action, ShortcutBinding)] = [
            (.addSnapshot, shortcuts.addSnapshot),
            (.copyCurrentContext, shortcuts.copyCurrentContext)
        ]
        for (action, binding) in ordered {
            if !register(binding: binding, action: action) {
                failed.append(action)
            }
        }
        return failed
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard
                    let eventRef,
                    let userData
                else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(eventRef: eventRef)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        if status != noErr {
            AppLogger.error("Failed to install global hotkey handler status=\(status)")
        }
    }

    private func handle(eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else {
            return status
        }
        guard hotKeyID.signature == Constants.signature else {
            return OSStatus(eventNotHandledErr)
        }
        guard let action = Action.allCases.first(where: { $0.id == hotKeyID.id }) else {
            return OSStatus(eventNotHandledErr)
        }
        onTrigger(action)
        return noErr
    }

    private func register(binding: ShortcutBinding, action: Action) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            carbonModifiers(from: binding),
            EventHotKeyID(signature: Constants.signature, id: action.id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            AppLogger.error("Failed to register global hotkey action=\(action) status=\(status)")
            return false
        }
        hotKeyRefs[action] = ref
        return true
    }

    private func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    private func carbonModifiers(from binding: ShortcutBinding) -> UInt32 {
        var modifiers: UInt32 = 0
        if binding.command {
            modifiers |= UInt32(cmdKey)
        }
        if binding.option {
            modifiers |= UInt32(optionKey)
        }
        if binding.control {
            modifiers |= UInt32(controlKey)
        }
        if binding.shift {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }
}
