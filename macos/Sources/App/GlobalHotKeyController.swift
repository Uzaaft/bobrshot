import Carbon
import Foundation

@MainActor
struct GlobalHotKeyActions {
    let captureRegion: () -> Void
    let captureWindow: () -> Void
    let captureDisplay: () -> Void
    let recordRegion: () -> Void
}

@MainActor
final class GlobalHotKeyController {
    private enum Identifier: UInt32, CaseIterable {
        case captureRegion = 1
        case captureWindow = 2
        case captureDisplay = 3
        case recordRegion = 4

        var keyCode: UInt32 {
            switch self {
            case .captureRegion: UInt32(kVK_ANSI_1)
            case .captureWindow: UInt32(kVK_ANSI_2)
            case .captureDisplay: UInt32(kVK_ANSI_3)
            case .recordRegion: UInt32(kVK_ANSI_4)
            }
        }
    }

    private static let signature: OSType = 0x424F4252  // "BOBR"

    private let actions: GlobalHotKeyActions
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []

    init(actions: GlobalHotKeyActions) {
        self.actions = actions
    }

    func register() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        let modifiers = UInt32(cmdKey | shiftKey | controlKey)
        for identifier in Identifier.allCases {
            var reference: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: identifier.rawValue)
            guard
                RegisterEventHotKey(
                    identifier.keyCode,
                    modifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &reference
                ) == noErr,
                let reference
            else { continue }
            hotKeys.append(reference)
        }
    }

    private func perform(_ identifier: Identifier) {
        switch identifier {
        case .captureRegion: actions.captureRegion()
        case .captureWindow: actions.captureWindow()
        case .captureDisplay: actions.captureDisplay()
        case .recordRegion: actions.recordRegion()
        }
    }

    private static let eventCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard result == noErr, hotKeyID.signature == signature,
            let identifier = Identifier(rawValue: hotKeyID.id)
        else { return OSStatus(eventNotHandledErr) }

        let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData)
            .takeUnretainedValue()
        MainActor.assumeIsolated {
            controller.perform(identifier)
        }
        return noErr
    }
}
