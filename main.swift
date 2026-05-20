import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import IOKit
import IOKit.hid
// build swiftc -O -parse-as-library -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework IOKit main.swift -o mod-drag -module-cache-path ./.module-cache
private let axFrameAttribute: CFString = "AXFrame" as CFString
private let inputRunLoopMode = CFRunLoopMode.commonModes.rawValue
private let trackedModifierFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
private let modDragVersion = "0.1.2"

private func normalizedModifierFlags(_ flags: CGEventFlags) -> CGEventFlags {
    flags.intersection(trackedModifierFlags)
}

private func modifierTitle(_ flags: CGEventFlags) -> String {
    let normalizedFlags = normalizedModifierFlags(flags)
    var parts: [String] = []

    if normalizedFlags.contains(.maskControl) {
        parts.append("Ctrl")
    }
    if normalizedFlags.contains(.maskAlternate) {
        parts.append("Option")
    }
    if normalizedFlags.contains(.maskShift) {
        parts.append("Shift")
    }
    if normalizedFlags.contains(.maskCommand) {
        parts.append("Cmd")
    }

    return parts.isEmpty ? "No modifiers" : parts.joined(separator: " + ")
}

private func keyName(for keyCode: UInt16) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 31: return "O"
    case 32: return "U"
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 40: return "K"
    case 45: return "N"
    case 46: return "M"
    case 48: return "Tab"
    case 49: return "Space"
    case 51: return "Delete"
    case 53: return "Esc"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 99: return "F8"
    case 100: return "F9"
    case 101: return "F10"
    case 103: return "F11"
    case 109: return "F12"
    case 123: return "Left Arrow"
    case 124: return "Right Arrow"
    case 125: return "Down Arrow"
    case 126: return "Up Arrow"
    default: return "Key(\(keyCode))"
    }
}

enum ShortcutAction: String {
    case move
    case resize
    case zoom

    static let allCases: [ShortcutAction] = [.move, .resize, .zoom]

    var title: String {
        switch self {
        case .move: return "Move"
        case .resize: return "Resize"
        case .zoom: return "Maximize"
        }
    }
}

struct ModifierPreset: CaseIterable, Equatable {
    let id: String
    let title: String
    let flags: CGEventFlags

    static let command = ModifierPreset(id: "command", title: "Cmd", flags: [.maskCommand])
    static let controlCommand = ModifierPreset(id: "controlCommand", title: "Ctrl + Cmd", flags: [.maskControl, .maskCommand])
    static let optionCommand = ModifierPreset(id: "optionCommand", title: "Option + Cmd", flags: [.maskAlternate, .maskCommand])
    static let shiftCommand = ModifierPreset(id: "shiftCommand", title: "Shift + Cmd", flags: [.maskShift, .maskCommand])

    static let allCases: [ModifierPreset] = [
        .command,
        .controlCommand,
        .optionCommand,
        .shiftCommand
    ]

    static func preset(id: String, fallback: ModifierPreset) -> ModifierPreset {
        allCases.first { $0.id == id } ?? fallback
    }
}

final class ModDragSettings {
    private enum Key {
        static let sideButtonNumber = "sideButtonNumber"
        static let moveButtonNumber = "moveButtonNumber"
        static let resizeButtonNumber = "resizeButtonNumber"
        static let zoomButtonNumber = "zoomButtonNumber"
        static let dragModifierPreset = "dragModifierPreset"
        static let resizeModifierPreset = "resizeModifierPreset"
        static let dragModifierFlags = "dragModifierFlags"
        static let resizeModifierFlags = "resizeModifierFlags"
        static let zoomModifierFlags = "zoomModifierFlags"
        static let dragKeyCode = "dragKeyCode"
        static let resizeKeyCode = "resizeKeyCode"
        static let zoomKeyCode = "zoomKeyCode"
        static let minimumWindowSize = "minimumWindowSize"
        static let hidFallbackEnabled = "hidFallbackEnabled"
    }

    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?
    var recordingAction: ShortcutAction? {
        didSet { onChange?() }
    }

    var sideButtonNumber: Int64 {
        didSet {
            defaults.set(sideButtonNumber, forKey: Key.sideButtonNumber)
            onChange?()
        }
    }

    var moveButtonNumber: Int64 {
        didSet {
            defaults.set(moveButtonNumber, forKey: Key.moveButtonNumber)
            onChange?()
        }
    }

    var resizeButtonNumber: Int64 {
        didSet {
            defaults.set(resizeButtonNumber, forKey: Key.resizeButtonNumber)
            onChange?()
        }
    }

    var zoomButtonNumber: Int64 {
        didSet {
            defaults.set(zoomButtonNumber, forKey: Key.zoomButtonNumber)
            onChange?()
        }
    }

    var dragModifierFlags: CGEventFlags {
        didSet {
            defaults.set(dragModifierFlags.rawValue, forKey: Key.dragModifierFlags)
            onChange?()
        }
    }

    var resizeModifierFlags: CGEventFlags {
        didSet {
            defaults.set(resizeModifierFlags.rawValue, forKey: Key.resizeModifierFlags)
            onChange?()
        }
    }

    var zoomModifierFlags: CGEventFlags {
        didSet {
            defaults.set(zoomModifierFlags.rawValue, forKey: Key.zoomModifierFlags)
            onChange?()
        }
    }

    var dragKeyCode: UInt16? {
        didSet { saveKeyCode(dragKeyCode, key: Key.dragKeyCode) }
    }

    var resizeKeyCode: UInt16? {
        didSet { saveKeyCode(resizeKeyCode, key: Key.resizeKeyCode) }
    }

    var zoomKeyCode: UInt16? {
        didSet { saveKeyCode(zoomKeyCode, key: Key.zoomKeyCode) }
    }

    var minimumWindowSize: CGFloat {
        didSet {
            defaults.set(Double(minimumWindowSize), forKey: Key.minimumWindowSize)
            onChange?()
        }
    }

    var hidFallbackEnabled: Bool {
        didSet {
            defaults.set(hidFallbackEnabled, forKey: Key.hidFallbackEnabled)
            onChange?()
        }
    }

    init() {
        let savedButtonNumber = defaults.object(forKey: Key.sideButtonNumber) as? NSNumber
        sideButtonNumber = savedButtonNumber?.int64Value ?? 3
        let legacyButtonNumber = sideButtonNumber
        moveButtonNumber = (defaults.object(forKey: Key.moveButtonNumber) as? NSNumber)?.int64Value ?? legacyButtonNumber
        resizeButtonNumber = (defaults.object(forKey: Key.resizeButtonNumber) as? NSNumber)?.int64Value ?? legacyButtonNumber
        zoomButtonNumber = (defaults.object(forKey: Key.zoomButtonNumber) as? NSNumber)?.int64Value ?? legacyButtonNumber

        dragModifierFlags = Self.loadModifierFlags(
            defaults: defaults,
            rawKey: Key.dragModifierFlags,
            legacyPresetKey: Key.dragModifierPreset,
            fallback: .command
        )
        resizeModifierFlags = Self.loadModifierFlags(
            defaults: defaults,
            rawKey: Key.resizeModifierFlags,
            legacyPresetKey: Key.resizeModifierPreset,
            fallback: .controlCommand
        )
        zoomModifierFlags = Self.loadModifierFlags(
            defaults: defaults,
            rawKey: Key.zoomModifierFlags,
            legacyPresetKey: nil,
            fallback: .command
        )
        dragKeyCode = Self.loadKeyCode(defaults: defaults, key: Key.dragKeyCode)
        resizeKeyCode = Self.loadKeyCode(defaults: defaults, key: Key.resizeKeyCode)
        zoomKeyCode = Self.loadKeyCode(defaults: defaults, key: Key.zoomKeyCode)

        let savedMinimumSize = defaults.double(forKey: Key.minimumWindowSize)
        minimumWindowSize = savedMinimumSize > 0 ? CGFloat(savedMinimumSize) : 100

        if defaults.object(forKey: Key.hidFallbackEnabled) == nil {
            hidFallbackEnabled = true
        } else {
            hidFallbackEnabled = defaults.bool(forKey: Key.hidFallbackEnabled)
        }
    }

    func resetToDefaults() {
        sideButtonNumber = 3
        moveButtonNumber = 3
        resizeButtonNumber = 3
        zoomButtonNumber = 3
        dragModifierFlags = ModifierPreset.command.flags
        resizeModifierFlags = ModifierPreset.controlCommand.flags
        zoomModifierFlags = ModifierPreset.command.flags
        dragKeyCode = nil
        resizeKeyCode = nil
        zoomKeyCode = nil
        minimumWindowSize = 100
        hidFallbackEnabled = true
        recordingAction = nil
    }

    func flags(for action: ShortcutAction) -> CGEventFlags {
        switch action {
        case .move: return dragModifierFlags
        case .resize: return resizeModifierFlags
        case .zoom: return zoomModifierFlags
        }
    }

    func keyCode(for action: ShortcutAction) -> UInt16? {
        switch action {
        case .move: return dragKeyCode
        case .resize: return resizeKeyCode
        case .zoom: return zoomKeyCode
        }
    }

    func buttonNumber(for action: ShortcutAction) -> Int64 {
        switch action {
        case .move: return moveButtonNumber
        case .resize: return resizeButtonNumber
        case .zoom: return zoomButtonNumber
        }
    }

    func setFlags(_ flags: CGEventFlags, for action: ShortcutAction) {
        let normalizedFlags = normalizedModifierFlags(flags)
        switch action {
        case .move:
            dragModifierFlags = normalizedFlags
        case .resize:
            resizeModifierFlags = normalizedFlags
        case .zoom:
            zoomModifierFlags = normalizedFlags
        }
    }

    func setKeyCode(_ keyCode: UInt16?, for action: ShortcutAction) {
        switch action {
        case .move:
            dragKeyCode = keyCode
        case .resize:
            resizeKeyCode = keyCode
        case .zoom:
            zoomKeyCode = keyCode
        }
    }

    func setButtonNumber(_ buttonNumber: Int64, for action: ShortcutAction) {
        switch action {
        case .move:
            moveButtonNumber = buttonNumber
        case .resize:
            resizeButtonNumber = buttonNumber
        case .zoom:
            zoomButtonNumber = buttonNumber
        }
    }

    private func saveKeyCode(_ keyCode: UInt16?, key: String) {
        if let keyCode {
            defaults.set(Int(keyCode), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        onChange?()
    }

    private static func loadKeyCode(defaults: UserDefaults, key: String) -> UInt16? {
        guard let savedValue = defaults.object(forKey: key) as? NSNumber else {
            return nil
        }
        return UInt16(savedValue.intValue)
    }

    private static func loadModifierFlags(
        defaults: UserDefaults,
        rawKey: String,
        legacyPresetKey: String?,
        fallback: ModifierPreset
    ) -> CGEventFlags {
        if let rawValue = defaults.object(forKey: rawKey) as? NSNumber {
            return normalizedModifierFlags(CGEventFlags(rawValue: rawValue.uint64Value))
        }

        if let legacyPresetKey {
            let preset = ModifierPreset.preset(id: defaults.string(forKey: legacyPresetKey) ?? "", fallback: fallback)
            return preset.flags
        }

        return fallback.flags
    }
}

enum Log {
    private static var isEnabled = false

    static func configure(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    static func info(_ message: String) {
        guard isEnabled else { return }
        emit(message)
    }

    static func always(_ message: String) {
        emit(message)
    }

    private static func emit(_ message: String) {
        if message.hasSuffix("\n") {
            fputs(message, stderr)
        } else {
            fputs(message + "\n", stderr)
        }
    }
}

// MARK: - Configuration

struct CustomKeyConfiguration {
    let vendorID: UInt32?
    let productID: UInt32?
    let locationID: UInt32?
    let productSubstring: String?
    let prefix: [UInt8]
    let stateOffset: Int
    let reportBufferLength: Int
    let logOpenErrors: Bool
}

struct WindowDraggerConfiguration {
    let customKey: CustomKeyConfiguration
    let emergencyStopKeyCode: UInt16
    let minimumWindowSize: CGSize
    let updateInterval: CFTimeInterval

    static let `default` = WindowDraggerConfiguration(
        customKey: CustomKeyConfiguration(
            // LocationID changes when the mouse/receiver is reconnected, so prefer stable IDs.
            vendorID: 0x046D,
            productID: nil,
            locationID: nil,
            productSubstring: nil,
            prefix: [0x11, 0x02, 0x0D, 0x00, 0x00],
            stateOffset: 0,
            reportBufferLength: 512,
            logOpenErrors: false
        ),
        emergencyStopKeyCode: 53,
        minimumWindowSize: CGSize(width: 100, height: 100),
        updateInterval: 1.0 / 120.0
    )
}

// MARK: - HID Custom Key Listener

final class CustomKeyListener {
    typealias StateChangeHandler = (Bool) -> Void

    private let configuration: CustomKeyConfiguration
    private let stateChangeHandler: StateChangeHandler

    private var manager: IOHIDManager?
    private var buffers: [IOHIDDevice: UnsafeMutablePointer<UInt8>] = [:]
    private var deviceStates: [IOHIDDevice: Bool] = [:]
    private var aggregateState = false

    init(configuration: CustomKeyConfiguration, stateChangeHandler: @escaping StateChangeHandler) {
        self.configuration = configuration
        self.stateChangeHandler = stateChangeHandler
    }

    deinit {
        cleanupDevices()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), inputRunLoopMode)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func start() {
        guard manager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        IOHIDManagerSetDeviceMatchingMultiple(manager, [matchingDictionary()] as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, CustomKeyListener.deviceMatchingCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, CustomKeyListener.deviceRemovalCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), inputRunLoopMode)

        primeExistingDevices(manager: manager, context: context)
    }

    private func primeExistingDevices(manager: IOHIDManager, context: UnsafeMutableRawPointer) {
        guard let devices = IOHIDManagerCopyDevices(manager) else { return }
        let set: CFSet = devices
        let count = CFSetGetCount(set)
        guard count > 0 else { return }
        let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: count)
        CFSetGetValues(set, pointer)
        for index in 0..<count {
            if let raw = pointer.advanced(by: index).pointee {
                let device = unsafeBitCast(raw, to: IOHIDDevice.self)
                CustomKeyListener.deviceMatchingCallback(context, kIOReturnSuccess, nil, device)
            }
        }
        pointer.deallocate()
    }

    private func cleanupDevices() {
        for (device, buffer) in buffers {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), inputRunLoopMode)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            buffer.deallocate()
        }
        buffers.removeAll()
        deviceStates.removeAll()
        aggregateState = false
    }

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        guard buffers[device] == nil, matchesDevice(device) else { return }

        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            if configuration.logOpenErrors {
                let message = String(format: "IOHIDDeviceOpen failed: 0x%08x", openResult)
                Log.info(message)
            }
            return
        }

        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: configuration.reportBufferLength)
        reportBuffer.initialize(repeating: 0, count: configuration.reportBufferLength)
        buffers[device] = reportBuffer
        deviceStates[device] = false

        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportBuffer,
            CFIndex(configuration.reportBufferLength),
            CustomKeyListener.reportCallback,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), inputRunLoopMode)
    }

    private func handleDeviceRemoval(_ device: IOHIDDevice) {
        guard let buffer = buffers.removeValue(forKey: device) else { return }

        let wasPressed = deviceStates.removeValue(forKey: device) ?? false

        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), inputRunLoopMode)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        buffer.deallocate()

        if wasPressed {
            publishAggregateStateIfNeeded()
        }
    }

    private func matchingDictionary() -> CFDictionary {
        let match = NSMutableDictionary()

        if let vendorID = configuration.vendorID {
            match[kIOHIDVendorIDKey] = vendorID
        }

        if let productID = configuration.productID {
            match[kIOHIDProductIDKey] = productID
        }

        return match as CFDictionary
    }

    private func matchesDevice(_ device: IOHIDDevice) -> Bool {
        if let locationID = configuration.locationID, deviceUInt32Property(device, key: kIOHIDLocationIDKey) != locationID {
            return false
        }

        if let productSubstring = configuration.productSubstring, !productSubstring.isEmpty {
            guard let product = deviceStringProperty(device, key: kIOHIDProductKey),
                  product.localizedCaseInsensitiveContains(productSubstring) else {
                return false
            }
        }

        return true
    }

    private func deviceUInt32Property(_ device: IOHIDDevice, key: String) -> UInt32? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString),
              CFGetTypeID(value) == CFNumberGetTypeID() else {
            return nil
        }
        var location: UInt32 = 0
        guard CFNumberGetValue((value as! CFNumber), .intType, &location) else {
            return nil
        }
        return location
    }

    private func deviceStringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString),
              CFGetTypeID(value) == CFStringGetTypeID() else {
            return nil
        }
        return value as? String
    }

    private func handleReport(device: IOHIDDevice?, reportPointer: UnsafeMutablePointer<UInt8>, length: CFIndex) {
        guard let device, buffers[device] != nil else { return }

        let prefixSize = configuration.prefix.count
        let index = prefixSize + configuration.stateOffset

        if length < prefixSize + 1 + configuration.stateOffset || index >= length {
            return
        }

        for i in 0..<prefixSize where reportPointer[i] != configuration.prefix[i] {
            return
        }

        let state = reportPointer[index] != 0

        if deviceStates[device] == state {
            return
        }

        deviceStates[device] = state
        publishAggregateStateIfNeeded()
    }

    private func publishAggregateStateIfNeeded() {
        let newAggregateState = deviceStates.values.contains(true)
        if newAggregateState != aggregateState {
            aggregateState = newAggregateState
            stateChangeHandler(newAggregateState)
        }
    }

    private static let deviceMatchingCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let listener = Unmanaged<CustomKeyListener>.fromOpaque(context).takeUnretainedValue()
        listener.handleDeviceMatched(device)
    }

    private static let deviceRemovalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let listener = Unmanaged<CustomKeyListener>.fromOpaque(context).takeUnretainedValue()
        listener.handleDeviceRemoval(device)
    }

    private static let reportCallback: IOHIDReportCallback = { context, _, sender, _, _, reportPointer, reportLength in
        guard let context else { return }
        let listener = Unmanaged<CustomKeyListener>.fromOpaque(context).takeUnretainedValue()
        let device = sender.map { unsafeBitCast($0, to: IOHIDDevice.self) }
        listener.handleReport(device: device, reportPointer: reportPointer, length: reportLength)
    }
}

// MARK: - Menu Bar

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let settings: ModDragSettings

    init(settings: ModDragSettings) {
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        settings.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.configureMenu()
            }
        }
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }

        if let image = NSImage(
            systemSymbolName: "cursorarrow.motionlines",
            accessibilityDescription: "ModDrag"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "MD"
        }
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(makeHeaderItem())
        if let recordingAction = settings.recordingAction {
            menu.addItem(makeDisabledItem("Recording \(recordingAction.title): press keys + side button", symbolName: "record.circle"))
        }
        menu.addItem(makeDisabledItem("Move  \(shortcutDescription(.move))", symbolName: "arrow.up.left.and.arrow.down.right"))
        menu.addItem(makeDisabledItem("Resize  \(shortcutDescription(.resize))", symbolName: "arrow.down.right.and.arrow.up.left"))
        menu.addItem(makeDisabledItem("Maximize  double \(shortcutDescription(.zoom))", symbolName: "arrow.up.left.and.arrow.down.right.magnifyingglass"))
        menu.addItem(makeDisabledItem("Minimum size  \(Int(settings.minimumWindowSize))x\(Int(settings.minimumWindowSize))", symbolName: "rectangle.compress.vertical"))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeRecordItem(.move))
        menu.addItem(makeRecordItem(.resize))
        menu.addItem(makeRecordItem(.zoom))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeSideButtonMenu(title: "Move Button", action: .move))
        menu.addItem(makeSideButtonMenu(title: "Resize Button", action: .resize))
        menu.addItem(makeSideButtonMenu(title: "Maximize Button", action: .zoom))
        menu.addItem(makeModifierMenu(title: "Move Modifier", symbolName: "move.3d", action: #selector(setMoveModifier(_:)), selectedFlags: settings.dragModifierFlags))
        menu.addItem(makeModifierMenu(title: "Resize Modifier", symbolName: "arrow.up.left.and.arrow.down.right", action: #selector(setResizeModifier(_:)), selectedFlags: settings.resizeModifierFlags))
        menu.addItem(makeModifierMenu(title: "Maximize Modifier", symbolName: "arrow.up.left.and.arrow.down.right.magnifyingglass", action: #selector(setZoomModifier(_:)), selectedFlags: settings.zoomModifierFlags))
        menu.addItem(makeMinimumSizeMenu())

        menu.addItem(NSMenuItem.separator())
        let hidFallbackItem = makeActionItem("Logitech HID Fallback", symbolName: "computermouse", action: #selector(toggleHIDFallback))
        hidFallbackItem.target = self
        hidFallbackItem.state = settings.hidFallbackEnabled ? .on : .off
        menu.addItem(hidFallbackItem)

        menu.addItem(makeActionItem("Open Accessibility Settings", symbolName: "hand.raised", action: #selector(openAccessibilitySettings)))
        menu.addItem(makeActionItem("Reset Defaults", symbolName: "arrow.counterclockwise", action: #selector(resetDefaults)))

        menu.addItem(NSMenuItem.separator())
        let quitItem = makeActionItem("Quit ModDrag", symbolName: "power", action: #selector(quit))
        quitItem.keyEquivalent = "q"
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    private func shortcutDescription(_ action: ShortcutAction) -> String {
        var parts: [String] = []
        let modifiers = modifierTitle(settings.flags(for: action))
        if modifiers != "No modifiers" {
            parts.append(modifiers)
        }
        if let keyCode = settings.keyCode(for: action) {
            parts.append(keyName(for: keyCode))
        }
        parts.append("Button \(settings.buttonNumber(for: action))")
        return parts.joined(separator: " + ")
    }

    private func makeRecordItem(_ action: ShortcutAction) -> NSMenuItem {
        let title: String
        if settings.recordingAction == action {
            title = "Recording \(action.title)..."
        } else {
            title = "Record \(action.title) Shortcut"
        }

        let item = makeActionItem(title, symbolName: "record.circle", action: #selector(recordShortcut(_:)))
        item.representedObject = action.rawValue
        item.state = settings.recordingAction == action ? .on : .off
        return item
    }

    private func makeSideButtonMenu(title: String, action: ShortcutAction) -> NSMenuItem {
        let item = makeParentItem(title, symbolName: "button.horizontal")
        let submenu = NSMenu()

        for buttonNumber in [3, 4, 5, 6, 7] {
            let buttonItem = makeActionItem("Button \(buttonNumber)", symbolName: buttonNumber == 3 ? "checkmark.circle" : "circle", action: #selector(setSideButton(_:)))
            buttonItem.target = self
            buttonItem.representedObject = "\(action.rawValue):\(buttonNumber)"
            buttonItem.state = settings.buttonNumber(for: action) == Int64(buttonNumber) ? .on : .off
            submenu.addItem(buttonItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeModifierMenu(title: String, symbolName: String, action: Selector, selectedFlags: CGEventFlags) -> NSMenuItem {
        let item = makeParentItem(title, symbolName: symbolName)
        let submenu = NSMenu()

        for preset in ModifierPreset.allCases {
            let presetItem = makeActionItem(preset.title, symbolName: "command", action: action)
            presetItem.target = self
            presetItem.representedObject = preset.id
            presetItem.state = normalizedModifierFlags(preset.flags).rawValue == normalizedModifierFlags(selectedFlags).rawValue ? .on : .off
            submenu.addItem(presetItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeMinimumSizeMenu() -> NSMenuItem {
        let item = makeParentItem("Minimum Window Size", symbolName: "rectangle.resize")
        let submenu = NSMenu()

        for size in [80, 100, 140, 180] {
            let sizeItem = makeActionItem("\(size)x\(size)", symbolName: "rectangle", action: #selector(setMinimumSize(_:)))
            sizeItem.target = self
            sizeItem.representedObject = size
            sizeItem.state = Int(settings.minimumWindowSize) == size ? .on : .off
            submenu.addItem(sizeItem)
        }

        item.submenu = submenu
        return item
    }

    private func makeHeaderItem() -> NSMenuItem {
        let item = makeDisabledItem("ModDrag Running", symbolName: "cursorarrow.motionlines")
        item.attributedTitle = NSAttributedString(
            string: "ModDrag Running",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor
            ]
        )
        return item
    }

    private func makeParentItem(_ title: String, symbolName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = menuImage(symbolName)
        item.isEnabled = true
        return item
    }

    private func makeDisabledItem(_ title: String, symbolName: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = menuImage(symbolName)
        item.isEnabled = false
        return item
    }

    private func makeActionItem(_ title: String, symbolName: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.image = menuImage(symbolName)
        item.target = self
        item.isEnabled = true
        return item
    }

    private func menuImage(_ symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        configureMenu()
    }

    @objc private func setSideButton(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let action = ShortcutAction(rawValue: String(parts[0])),
              let buttonNumber = Int64(parts[1]) else {
            return
        }
        settings.setButtonNumber(buttonNumber, for: action)
    }

    @objc private func setMoveModifier(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.dragModifierFlags = ModifierPreset.preset(id: id, fallback: .command).flags
    }

    @objc private func setResizeModifier(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.resizeModifierFlags = ModifierPreset.preset(id: id, fallback: .controlCommand).flags
    }

    @objc private func setZoomModifier(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        settings.zoomModifierFlags = ModifierPreset.preset(id: id, fallback: .command).flags
    }

    @objc private func recordShortcut(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = ShortcutAction(rawValue: rawValue) else {
            return
        }
        settings.recordingAction = settings.recordingAction == action ? nil : action
    }

    @objc private func setMinimumSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Int else { return }
        settings.minimumWindowSize = CGFloat(size)
        rebuildMenu()
    }

    @objc private func toggleHIDFallback() {
        settings.hidFallbackEnabled.toggle()
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func resetDefaults() {
        settings.resetToDefaults()
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - State Management
enum DraggerState {
    case idle
    case armed
    case dragging
    case resizeArmed
    case resizing
}

// MARK: - Main Window Dragger
class WindowDragger {
    private let configuration: WindowDraggerConfiguration
    private let customKeyConfiguration: CustomKeyConfiguration
    private let settings: ModDragSettings
    private let emergencyStopKeyCode: UInt16
    private let updateInterval: CFTimeInterval

    private var state: DraggerState = .idle
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var movementTimer: CFRunLoopTimer?
    
    // Drag state
    private var initialMousePosition: CGPoint = .zero
    private var initialWindowOrigin: CGPoint = .zero
    private var capturedWindow: AXUIElement?
    private var capturedPID: pid_t = 0
    
    // Resize state
    private var initialWindowSize: CGSize = .zero
    
    // Mouse coalescing
    private var pendingMouseLocation: CGPoint?
    
    // Custom key tracking
    private var customKeyListener: CustomKeyListener?
    private var customKeyActive = false
    private var commandActive = false
    private var controlActive = false
    private var optionActive = false
    private var shiftActive = false
    private var pressedKeyCodes: Set<UInt16> = []
    private var activeButtonNumber: Int64?
    private var lastShortcutTapTime: CFAbsoluteTime = 0
    private var savedWindowFrames: [CFHashCode: CGRect] = [:]

    private var dragShortcutActive: Bool {
        shortcutActive(.move)
    }

    private var resizeShortcutActive: Bool {
        shortcutActive(.resize)
    }

    private var zoomShortcutActive: Bool {
        shortcutActive(.zoom)
    }

    init(configuration: WindowDraggerConfiguration = .default, settings: ModDragSettings) {
        self.configuration = configuration
        self.settings = settings
        self.customKeyConfiguration = configuration.customKey
        self.emergencyStopKeyCode = configuration.emergencyStopKeyCode
        self.updateInterval = configuration.updateInterval
    }
    
    func start() {
        // Check accessibility permissions
        guard checkAccessibilityPermissions() else {
            return
        }
        
        // Create event tap
        refreshModifierState()
        setupEventTap()
        setupCustomKeyListener()
        
        // Start run loop
        Log.always("Window Dragger started.")
        Log.always("Hold Cmd + the custom mouse key (\(customKeyTargetDescription())) to drag windows.")
        Log.always("Hold Ctrl + Cmd + the same custom mouse key to resize.")
        Log.always("Press \(emergencyStopDescription()) to stop the current operation, Ctrl+C to quit.")
    }
    
    private func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            Log.always("❌ Accessibility permission required!")
            Log.always("")
            Log.always("Please add this binary to System Settings → Privacy & Security → Accessibility:")
            Log.always("1. Run this binary once")
            Log.always("2. Open System Settings → Privacy & Security → Accessibility")
            Log.always("3. Add this binary to the list")
            Log.always("4. Restart this binary")
        }
        return trusted
    }
    
    private func emergencyStopDescription() -> String {
        keyName(for: emergencyStopKeyCode)
    }

    private func customKeyTargetDescription() -> String {
        var parts: [String] = []

        if let vendorID = customKeyConfiguration.vendorID {
            parts.append(String(format: "VID=0x%04X", vendorID))
        }

        if let productID = customKeyConfiguration.productID {
            parts.append(String(format: "PID=0x%04X", productID))
        }

        if let locationID = customKeyConfiguration.locationID {
            parts.append("LocationID=\(locationID)")
        }

        if let productSubstring = customKeyConfiguration.productSubstring, !productSubstring.isEmpty {
            parts.append("Product contains \"\(productSubstring)\"")
        }

        return parts.isEmpty ? "all HID devices, filtered by report prefix" : parts.joined(separator: ", ")
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.mouseMoved.rawValue) | 
                       (1 << CGEventType.flagsChanged.rawValue) |
                       (1 << CGEventType.otherMouseDown.rawValue) |
                       (1 << CGEventType.otherMouseUp.rawValue) |
                       (1 << CGEventType.leftMouseDragged.rawValue) |
                       (1 << CGEventType.rightMouseDragged.rawValue) |
                       (1 << CGEventType.otherMouseDragged.rawValue) |
                       (1 << CGEventType.keyDown.rawValue) |
                       (1 << CGEventType.keyUp.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: CGEventTapLocation(rawValue: 0)!, // kCGHIDEventTap
            place: CGEventTapPlacement(rawValue: 0)!, // kCGHeadInsertEventTap
            options: CGEventTapOptions(rawValue: 0)!, // kCGEventTapOptionDefault
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let dragger = Unmanaged<WindowDragger>.fromOpaque(refcon!).takeUnretainedValue()
                return dragger.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            Log.always("❌ Failed to create event tap")
            exit(1)
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        setupMovementTimer()
    }

    private func setupMovementTimer() {
        let callback: CFRunLoopTimerCallBack = { timer, context in
            guard let context else { return }
            let dragger = Unmanaged<WindowDragger>.fromOpaque(context).takeUnretainedValue()
            dragger.processPendingMouseMovement()
        }

        var context = CFRunLoopTimerContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        movementTimer = CFRunLoopTimerCreate(
            kCFAllocatorDefault,
            CFAbsoluteTimeGetCurrent() + updateInterval,
            updateInterval,
            0,
            0,
            callback,
            &context
        )

        if let movementTimer {
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), movementTimer, .commonModes)
        }
    }

    private func setupCustomKeyListener() {
        let listener = CustomKeyListener(configuration: customKeyConfiguration) { [weak self] isPressed in
            self?.handleCustomKeyStateChanged(isPressed: isPressed)
        }
        customKeyListener = listener
        listener.start()
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            refreshModifierState()
            stopCurrentOperation()
            if let tap = eventTap {
                Log.info("⚠️ Event tap disabled, re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

            if type == .keyDown {
                pressedKeyCodes.insert(keyCode)
            } else {
                pressedKeyCodes.remove(keyCode)
            }

            if type == .keyDown, keyCode == emergencyStopKeyCode {
                if state == .dragging || state == .resizing {
                    stopCurrentOperation()
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            if customKeyActive {
                handleShortcutStateChanged()
            }
        }

        if type == .flagsChanged {
            handleFlagsChanged(event: event)
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown || type == .otherMouseUp {
            return handleOtherMouseButton(type: type, event: event)
        }

        if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged || type == .otherMouseDragged {
            handleMouseMoved(event: event)
            return Unmanaged.passUnretained(event)
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    private func handleFlagsChanged(event: CGEvent) {
        let flags = event.flags
        let newCommandActive = flags.contains(.maskCommand)
        let newControlActive = flags.contains(.maskControl)
        let newOptionActive = flags.contains(.maskAlternate)
        let newShiftActive = flags.contains(.maskShift)

        if newCommandActive != commandActive ||
            newControlActive != controlActive ||
            newOptionActive != optionActive ||
            newShiftActive != shiftActive {
            commandActive = newCommandActive
            controlActive = newControlActive
            optionActive = newOptionActive
            shiftActive = newShiftActive
            handleShortcutStateChanged()
        }
    }

    private func refreshModifierState() {
        refreshModifierState(from: CGEventSource.flagsState(.hidSystemState))
    }

    private func refreshModifierState(from flags: CGEventFlags) {
        commandActive = flags.contains(.maskCommand)
        controlActive = flags.contains(.maskControl)
        optionActive = flags.contains(.maskAlternate)
        shiftActive = flags.contains(.maskShift)
    }

    private func modifiersMatch(_ expectedFlags: CGEventFlags) -> Bool {
        commandActive == expectedFlags.contains(.maskCommand) &&
            controlActive == expectedFlags.contains(.maskControl) &&
            optionActive == expectedFlags.contains(.maskAlternate) &&
            shiftActive == expectedFlags.contains(.maskShift)
    }

    private func keyMatches(_ expectedKeyCode: UInt16?) -> Bool {
        guard let expectedKeyCode else { return true }
        return pressedKeyCodes.contains(expectedKeyCode)
    }

    private func shortcutActive(_ action: ShortcutAction) -> Bool {
        customKeyActive &&
            activeButtonNumber == settings.buttonNumber(for: action) &&
            modifiersMatch(settings.flags(for: action)) &&
            keyMatches(settings.keyCode(for: action))
    }

    private func shortcutLogDescription(_ action: ShortcutAction) -> String {
        var parts: [String] = []
        let modifiers = modifierTitle(settings.flags(for: action))
        if modifiers != "No modifiers" {
            parts.append(modifiers)
        }
        if let keyCode = settings.keyCode(for: action) {
            parts.append(keyName(for: keyCode))
        }
        parts.append("Button \(settings.buttonNumber(for: action))")
        return parts.joined(separator: " + ")
    }

    private func handleOtherMouseButton(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        Log.info("Mouse button \(buttonNumber) \(type == .otherMouseDown ? "down" : "up")")

        refreshModifierState(from: event.flags)

        if type == .otherMouseDown, let recordingAction = settings.recordingAction {
            settings.setButtonNumber(buttonNumber, for: recordingAction)
            settings.setFlags(event.flags, for: recordingAction)
            settings.setKeyCode(pressedKeyCodes.sorted().first, for: recordingAction)
            settings.recordingAction = nil
            Log.info("Recorded \(recordingAction.title): \(shortcutLogDescription(recordingAction))")
            return nil
        }

        let isConfiguredButton = ShortcutAction.allCases.contains { settings.buttonNumber(for: $0) == buttonNumber }
        guard isConfiguredButton else {
            return Unmanaged.passUnretained(event)
        }

        if type == .otherMouseDown {
            activeButtonNumber = buttonNumber
            customKeyActive = true
        } else if activeButtonNumber == buttonNumber {
            customKeyActive = false
            activeButtonNumber = nil
        } else {
            return Unmanaged.passUnretained(event)
        }
        pendingMouseLocation = event.location

        if type == .otherMouseDown, zoomShortcutActive {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastShortcutTapTime <= 0.35 {
                lastShortcutTapTime = 0
                customKeyActive = false
                stopCurrentOperation()
                toggleZoom(at: event.location)
                return nil
            }
            lastShortcutTapTime = now
        }

        handleShortcutStateChanged()
        return nil
    }

    private func handleCustomKeyStateChanged(isPressed: Bool) {
        guard settings.hidFallbackEnabled else { return }

        if isPressed == customKeyActive {
            return
        }

        customKeyActive = isPressed
        activeButtonNumber = isPressed ? settings.buttonNumber(for: .move) : nil
        handleShortcutStateChanged()
    }

    private func deactivateShortcut() {
        switch state {
        case .dragging:
            stopDragging()
        case .resizing:
            stopResizing()
        case .armed, .resizeArmed:
            state = .idle
            Log.info("💤 Idle")
        case .idle:
            break
        }
    }

    private func handleShortcutStateChanged() {
        let shouldResize = resizeShortcutActive
        let shouldDrag = dragShortcutActive

        guard shouldResize || shouldDrag else {
            deactivateShortcut()
            return
        }

        guard let location = currentPointerLocation() else {
            if shouldResize {
                state = .resizeArmed
                Log.info("📏 Resize armed - move mouse over a window")
            } else {
                state = .armed
                Log.info("🔧 Armed - move mouse over a window")
            }
            return
        }

        if shouldResize {
            switch state {
            case .dragging:
                if let window = capturedWindow {
                    let windowRef = window
                    stopDragging()
                    if !startResizing(window: windowRef, initialMouse: location) {
                        state = .resizeArmed
                    }
                } else {
                    armForResizing(at: location)
                }
            case .armed, .idle:
                armForResizing(at: location)
            case .resizeArmed, .resizing:
                break
            }
        } else {
            switch state {
            case .resizing:
                if let window = capturedWindow {
                    let windowRef = window
                    stopResizing()
                    if !startDragging(window: windowRef, initialMouse: location) {
                        state = .armed
                    }
                } else {
                    armForDragging(at: location)
                }
            case .resizeArmed, .idle:
                armForDragging(at: location)
            case .armed, .dragging:
                break
            }
        }
    }

    private func currentPointerLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    private func armForDragging(at location: CGPoint) {
        if let window = hitTestWindow(at: location) {
            _ = startDragging(window: window, initialMouse: location)
        } else {
            state = .armed
            Log.info("🔧 Armed - move mouse over a window")
        }
    }

    private func armForResizing(at location: CGPoint) {
        if let window = hitTestWindow(at: location) {
            _ = startResizing(window: window, initialMouse: location)
        } else {
            state = .resizeArmed
            Log.info("📏 Resize armed - move mouse over a window")
        }
    }
    
    private func handleMouseMoved(event: CGEvent) {
        guard customKeyActive || state != .idle else { return }
        pendingMouseLocation = event.location
    }

    private func processPendingMouseMovement() {
        guard let mouseLocation = pendingMouseLocation else { return }

        let shouldResize = resizeShortcutActive
        let shouldDrag = dragShortcutActive

        // Dynamic switch with priority for dragging
        if shouldDrag {
            switch state {
            case .resizing:
                if let window = capturedWindow {
                    let windowRef = window
                    stopResizing()
                    if !startDragging(window: windowRef, initialMouse: mouseLocation) {
                        state = .armed
                    }
                } else {
                    stopResizing()
                    state = .armed
                    Log.info("🔧 Armed - move mouse over a window")
                }
                return
            case .resizeArmed:
                state = .armed
                Log.info("🔧 Armed - move mouse over a window")
                return
            default:
                break
            }
        }

        switch state {
        case .armed:
            if shouldResize {
                state = .resizeArmed
                Log.info("📏 Resize armed - move mouse over a window")
            } else if shouldDrag {
                if let window = hitTestWindow(at: mouseLocation) {
                    _ = startDragging(window: window, initialMouse: mouseLocation)
                }
            } else {
                state = .idle
                Log.info("💤 Idle")
            }

        case .dragging:
            if shouldResize {
                if let window = capturedWindow {
                    let windowRef = window
                    stopDragging()
                    if !startResizing(window: windowRef, initialMouse: mouseLocation) {
                        state = .resizeArmed
                    }
                } else {
                    stopDragging()
                }
            } else if shouldDrag && capturedWindow != nil {
                updateWindowPosition(currentMouse: mouseLocation)
            } else {
                stopDragging()
            }

        case .resizeArmed:
            if shouldResize {
                if let window = hitTestWindow(at: mouseLocation) {
                    _ = startResizing(window: window, initialMouse: mouseLocation)
                }
            } else if shouldDrag {
                state = .armed
                Log.info("🔧 Armed - move mouse over a window")
            } else {
                state = .idle
                Log.info("💤 Idle")
            }

        case .resizing:
            if shouldResize && capturedWindow != nil {
                updateWindowSize(currentMouse: mouseLocation)
            } else {
                stopResizing()
            }
            
        case .idle:
            break
        }
    }
    
    private func hitTestWindow(at location: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(location.x), Float(location.y), &element)
        
        guard result == .success, let uiElement = element else {
            return nil
        }
        
        // Walk up to find window
        var currentElement = uiElement
        var fallbackWindow: AXUIElement?

        while true {
            if let resolvedWindow = resolveWindowElement(from: currentElement) {
                if isWindowMovable(resolvedWindow) {
                    return resolvedWindow
                }
                if fallbackWindow == nil {
                    fallbackWindow = resolvedWindow
                }
            }

            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &role)

            if let roleString = role as? String, roleString == kAXWindowRole {
                if isWindowMovable(currentElement) {
                    return currentElement
                }
                if fallbackWindow == nil {
                    fallbackWindow = currentElement
                }
                break
            }

            var parent: CFTypeRef?
            if AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parent) == .success,
               let parentElement = parent {
                currentElement = parentElement as! AXUIElement
            } else {
                break
            }
        }

        return fallbackWindow
    }
    
    private func resolveWindowElement(from element: AXUIElement) -> AXUIElement? {
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
           let value = windowRef {
            return unsafeBitCast(value, to: AXUIElement.self)
        }

        if AXUIElementCopyAttributeValue(element, kAXTopLevelUIElementAttribute as CFString, &windowRef) == .success,
           let value = windowRef {
            return unsafeBitCast(value, to: AXUIElement.self)
        }

        return nil
    }
    
    private func isWindowMovable(_ window: AXUIElement) -> Bool {
        // Check if window exposes position or frame information (required for moving/resizing)
        var position: CFTypeRef?
        var hasGeometry = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success

        if !hasGeometry {
            position = nil
            hasGeometry = AXUIElementCopyAttributeValue(window, axFrameAttribute, &position) == .success
        }

        guard hasGeometry else {
            return false
        }
        
        // Check if window is not minimized
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           let isMinimized = minimized as? Bool, isMinimized {
            return false
        }
        
        // Note: kAXFullscreenAttribute may not be available in all macOS versions
        // Skip fullscreen check for compatibility
        
        return true
    }
    
    private func startDragging(window: AXUIElement, initialMouse: CGPoint) -> Bool {
        // Get window position and PID
        guard let windowOrigin = getWindowOrigin(window),
              let pid = getWindowPID(window) else {
            Log.info("❌ Failed to get window info")
            return false
        }

        // Store drag state
        capturedWindow = window
        capturedPID = pid
        initialMousePosition = initialMouse
        initialWindowOrigin = windowOrigin
        state = .dragging
        
        Log.info("🎯 Dragging window (PID: \(pid))")
        return true
    }
    
    private func updateWindowPosition(currentMouse: CGPoint) {
        guard let window = capturedWindow else {
            stopDragging()
            return
        }
        
        // Calculate delta and new position
        let deltaX = currentMouse.x - initialMousePosition.x
        let deltaY = currentMouse.y - initialMousePosition.y
        
        let newOrigin = CGPoint(
            x: initialWindowOrigin.x + deltaX,
            y: initialWindowOrigin.y + deltaY
        )
        
        // Update window position
        if !setWindowOrigin(window: window, origin: newOrigin) {
            Log.info("⚠️ Failed to move window, stopping drag")
            stopDragging()
        }
    }

    private func stopDragging() {
        capturedWindow = nil
        capturedPID = 0
        initialMousePosition = .zero
        initialWindowOrigin = .zero
        state = .idle
        Log.info("💤 Idle")
    }
    
    // MARK: - Resize Functions
    
    private func startResizing(window: AXUIElement, initialMouse: CGPoint) -> Bool {
        // Get window size and PID
        guard let windowSize = getWindowSize(window),
              let pid = getWindowPID(window) else {
            Log.info("❌ Failed to get window info for resize")
            return false
        }

        // Store resize state
        capturedWindow = window
        capturedPID = pid
        initialMousePosition = initialMouse
        initialWindowSize = windowSize
        state = .resizing
        
        Log.info("📏 Resizing window (PID: \(pid))")
        return true
    }
    
    private func updateWindowSize(currentMouse: CGPoint) {
        guard let window = capturedWindow else {
            stopResizing()
            return
        }
        
        // Calculate delta and new size
        let deltaX = currentMouse.x - initialMousePosition.x
        let deltaY = currentMouse.y - initialMousePosition.y
        
        let newSize = CGSize(
            width: max(settings.minimumWindowSize, initialWindowSize.width + deltaX),
            height: max(settings.minimumWindowSize, initialWindowSize.height + deltaY)
        )
        
        // Update window size
        if !setWindowSize(window: window, size: newSize) {
            Log.info("⚠️ Failed to resize window, stopping resize")
            stopResizing()
        }
    }

    private func stopResizing() {
        capturedWindow = nil
        capturedPID = 0
        initialMousePosition = .zero
        initialWindowSize = .zero
        state = .idle
        Log.info("💤 Idle")
    }

    private func stopCurrentOperation() {
        switch state {
        case .dragging:
            stopDragging()
        case .resizing:
            stopResizing()
        default:
            state = .idle
            Log.info("💤 Idle")
        }
    }

    private func toggleZoom(at location: CGPoint) {
        guard let window = hitTestWindow(at: location),
              let currentFrame = getWindowFrame(window) else {
            Log.info("⚠️ Failed to find a window to maximize")
            return
        }

        let key = CFHash(window)

        if let savedFrame = savedWindowFrames.removeValue(forKey: key) {
            setWindowFrame(window, frame: savedFrame)
            Log.info("↩️ Restored window")
            return
        }

        guard let targetFrame = visibleFrameForAccessibility(at: location) else {
            Log.info("⚠️ Failed to resolve screen frame")
            return
        }

        savedWindowFrames[key] = currentFrame
        setWindowFrame(window, frame: targetFrame)
        Log.info("🔎 Maximized window")
    }

    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        guard let origin = getWindowOrigin(window),
              let size = getWindowSize(window) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func setWindowFrame(_ window: AXUIElement, frame: CGRect) {
        _ = setWindowOrigin(window: window, origin: frame.origin)
        _ = setWindowSize(window: window, size: frame.size)
    }

    private func visibleFrameForAccessibility(at location: CGPoint) -> CGRect? {
        guard let screen = screenContainingAccessibilityPoint(location) ?? NSScreen.main else {
            return nil
        }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let accessibilityOrigin = CGPoint(
            x: visibleFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY
        )

        return CGRect(origin: accessibilityOrigin, size: visibleFrame.size)
    }

    private func screenContainingAccessibilityPoint(_ location: CGPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            let screenFrame = screen.frame
            let convertedY = screenFrame.maxY - location.y
            let convertedPoint = CGPoint(x: location.x, y: convertedY)
            return screenFrame.contains(convertedPoint)
        }
    }
    
    // MARK: - Helper Functions
    
    private func getWindowOrigin(_ window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value) == .success,
           let rawValue = value {
            let axValue = unsafeBitCast(rawValue, to: AXValue.self)
            if AXValueGetType(axValue) == .cgPoint {
                var point = CGPoint.zero
                if AXValueGetValue(axValue, AXValueType.cgPoint, &point) {
                    return point
                }
            }
        }

        value = nil
        if AXUIElementCopyAttributeValue(window, axFrameAttribute, &value) == .success,
           let rawValue = value {
            let axValue = unsafeBitCast(rawValue, to: AXValue.self)
            if AXValueGetType(axValue) == .cgRect {
                var rect = CGRect.zero
                if AXValueGetValue(axValue, AXValueType.cgRect, &rect) {
                    return rect.origin
                }
            }
        }
        
        return nil
    }
    
    private func getWindowPID(_ window: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(window, &pid)
        return result == .success ? pid : nil
    }
    
    private func activateApp(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return
        }
        
        app.activate(options: [])
    }
    
    private func setWindowOrigin(window: AXUIElement, origin: CGPoint) -> Bool {
        var point = origin
        guard let positionValue = AXValueCreate(AXValueType.cgPoint, &point) else {
            return false
        }
        
        let result = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        return result == .success
    }
    
    private func getWindowSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success,
           let rawValue = value {
            let axValue = unsafeBitCast(rawValue, to: AXValue.self)
            if AXValueGetType(axValue) == .cgSize {
                var size = CGSize.zero
                if AXValueGetValue(axValue, AXValueType.cgSize, &size) {
                    return size
                }
            }
        }

        value = nil
        if AXUIElementCopyAttributeValue(window, axFrameAttribute, &value) == .success,
           let rawValue = value {
            let axValue = unsafeBitCast(rawValue, to: AXValue.self)
            if AXValueGetType(axValue) == .cgRect {
                var rect = CGRect.zero
                if AXValueGetValue(axValue, AXValueType.cgRect, &rect) {
                    return rect.size
                }
            }
        }
        
        return nil
    }
    
    private func setWindowSize(window: AXUIElement, size: CGSize) -> Bool {
        var cgSize = size
        guard let sizeValue = AXValueCreate(AXValueType.cgSize, &cgSize) else {
            return false
        }
        
        let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return result == .success
    }
}

// MARK: - Main
@main
struct Main {
    static func main() {
        Log.configure(isEnabled: CommandLine.arguments.contains("--log"))

        if CommandLine.arguments.contains("--version") {
            print("mod-drag \(modDragVersion)")
            return
        }

        if CommandLine.arguments.contains("--help") {
            print("""
            Usage: mod-drag [--log] [--version] [--help]

            ModDrag runs as a macOS menu bar app. Grant Accessibility access,
            then use the menu bar icon to configure side-button shortcuts.
            """)
            return
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let settings = ModDragSettings()
        let statusBarController = StatusBarController(settings: settings)
        let dragger = WindowDragger(settings: settings)
        
        // Handle Ctrl+C
        signal(SIGINT) { _ in
            Log.info("\n👋 Goodbye!")
            exit(0)
        }
        
        dragger.start()
        withExtendedLifetime(settings) {
            withExtendedLifetime(statusBarController) {
                app.run()
            }
        }
    }
}
