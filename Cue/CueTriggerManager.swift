import AppKit
import CoreGraphics
import Foundation
import Observation
import os

enum PushToTalkModifier: String, CaseIterable, Codable, Identifiable {
    case function
    case control
    case option
    case command

    static let defaultValue: Self = .function

    var id: Self { self }

    var title: String {
        switch self {
        case .function:
            return "Fn"
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .command:
            return "Command"
        }
    }

    var holdInstruction: String {
        "Hold \(title) in any app to record, then release to transcribe."
    }

    fileprivate var cgEventFlag: CGEventFlags {
        switch self {
        case .function:
            return .maskSecondaryFn
        case .control:
            return .maskControl
        case .option:
            return .maskAlternate
        case .command:
            return .maskCommand
        }
    }
}

protocol PushToTalkBindingService: AnyObject {
    func currentModifier() -> PushToTalkModifier
    func setModifier(_ modifier: PushToTalkModifier)
    func startMonitoring(onPress: @escaping () -> Void, onRelease: @escaping () -> Void)
    func refreshMonitoring()
}

final class LivePushToTalkBindingService: PushToTalkBindingService {
    private static let modifierDefaultsKey = "Cue.pushToTalkModifier"

    private let defaults: UserDefaults
    private let permissionChecker: () -> Bool

    private var modifier: PushToTalkModifier
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isSelectedModifierDown = false

    init(
        defaults: UserDefaults = .standard,
        permissionChecker: @escaping () -> Bool = { CGPreflightListenEventAccess() }
    ) {
        self.defaults = defaults
        self.permissionChecker = permissionChecker

        if
            let storedValue = defaults.string(forKey: Self.modifierDefaultsKey),
            let storedModifier = PushToTalkModifier(rawValue: storedValue)
        {
            modifier = storedModifier
        } else {
            modifier = .defaultValue
        }
    }

    deinit {
        tearDownEventTap()
    }

    func currentModifier() -> PushToTalkModifier {
        modifier
    }

    func setModifier(_ modifier: PushToTalkModifier) {
        self.modifier = modifier
        defaults.set(modifier.rawValue, forKey: Self.modifierDefaultsKey)
        isSelectedModifierDown = currentModifierDownState()
    }

    func startMonitoring(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        refreshMonitoring()
    }

    func refreshMonitoring() {
        guard permissionChecker() else {
            isSelectedModifierDown = false
            tearDownEventTap()
            return
        }

        isSelectedModifierDown = currentModifierDownState()

        if eventTap == nil {
            installEventTap()
        } else if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func installEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: pushToTalkEventTapCallback,
            userInfo: userInfo
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private func tearDownEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func currentModifierDownState() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(modifier.cgEventFlag)
    }

    fileprivate func handleEvent(type: CGEventType, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        case .flagsChanged:
            break
        default:
            return
        }

        let isModifierDown = flags.contains(modifier.cgEventFlag)

        guard isModifierDown != isSelectedModifierDown else {
            return
        }

        isSelectedModifierDown = isModifierDown

        if isModifierDown {
            onPress?()
        } else {
            onRelease?()
        }
    }
}

private func pushToTalkEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    _ = proxy

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<LivePushToTalkBindingService>.fromOpaque(userInfo).takeUnretainedValue()
    service.handleEvent(type: type, flags: event.flags)
    return Unmanaged.passUnretained(event)
}

final class DisabledPushToTalkBindingService: PushToTalkBindingService {
    private var modifier: PushToTalkModifier

    init(modifier: PushToTalkModifier = .defaultValue) {
        self.modifier = modifier
    }

    func currentModifier() -> PushToTalkModifier {
        modifier
    }

    func setModifier(_ modifier: PushToTalkModifier) {
        self.modifier = modifier
    }

    func startMonitoring(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        _ = onPress
        _ = onRelease
    }

    func refreshMonitoring() {}
}

@MainActor
@Observable
final class CueTriggerManager {
    var selectedModifier: PushToTalkModifier {
        didSet {
            guard selectedModifier != oldValue else {
                return
            }

            bindingService.setModifier(selectedModifier)
            logger.info("Push-to-talk modifier updated to \(self.selectedModifier.title, privacy: .public)")
        }
    }

    @ObservationIgnored private weak var appModel: CueAppModel?
    @ObservationIgnored private let bindingService: PushToTalkBindingService
    @ObservationIgnored private let logger = Logger(subsystem: "dev.sonawalla.Cue", category: "PushToTalk")
    @ObservationIgnored private let notificationCenter: NotificationCenter

    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    var selectedModifierTitle: String {
        selectedModifier.title
    }

    init(
        appModel: CueAppModel,
        bindingService: PushToTalkBindingService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.appModel = appModel
        self.bindingService = bindingService ?? LivePushToTalkBindingService()
        self.notificationCenter = notificationCenter
        self.selectedModifier = self.bindingService.currentModifier()

        self.bindingService.startMonitoring { [weak self] in
            guard let appModel = self?.appModel else {
                return
            }

            Task {
                await appModel.handlePushToTalkPressed()
            }
        } onRelease: { [weak self] in
            guard let appModel = self?.appModel else {
                return
            }

            Task {
                await appModel.handlePushToTalkReleased()
            }
        }

        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleApplicationDidBecomeActive()
            }
        }
    }

    private func handleApplicationDidBecomeActive() {
        bindingService.refreshMonitoring()
    }
}
