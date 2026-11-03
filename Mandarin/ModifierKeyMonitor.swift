import AppKit
import SwiftUI

enum DragMode: Equatable {
    case none
    case shift
    case command
    case control

    init(flags: NSEvent.ModifierFlags) {
        let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)
        if deviceIndependentFlags.contains(.shift) {
            self = .shift
        } else if deviceIndependentFlags.contains(.command) {
            self = .command
        } else if deviceIndependentFlags.contains(.control) {
            self = .control
        } else {
            self = .none
        }
    }

    var title: String {
        switch self {
        case .none: "Choose an action"
        case .shift: "Convert"
        case .command: "Tools"
        case .control: "File actions"
        }
    }

    var keyHint: String {
        switch self {
        case .none: "Hold Shift, Command, or Control — wheel opens at cursor"
        case .shift: "Convert wheel open at cursor"
        case .command: "Tools wheel open at cursor"
        case .control: "Actions wheel open at cursor"
        }
    }

    var accent: Color {
        switch self {
        case .none: .orange
        case .shift: .orange
        case .command: .purple
        case .control: .blue
        }
    }
}

struct WheelItem: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let isEnabled: Bool
}

final class FloatingWheelPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWheelController {
    static let shared = FloatingWheelController()

    private var panel: FloatingWheelPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let panelSize = NSSize(width: 320, height: 320)

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show<Content: View>(at cursorPoint: NSPoint? = nil, recenterIfFar: Bool = false, @ViewBuilder content: () -> Content) {
        let rootView = AnyView(content())

        if panel == nil {
            let newPanel = FloatingWheelPanel(
                contentRect: NSRect(origin: .zero, size: panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.level = .popUpMenu
            newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            newPanel.isMovableByWindowBackground = false
            newPanel.acceptsMouseMovedEvents = true
            newPanel.hidesOnDeactivate = false

            let host = NSHostingView(rootView: rootView)
            host.frame = NSRect(origin: .zero, size: panelSize)
            newPanel.contentView = host

            self.panel = newPanel
            self.hostingView = host
        } else {
            hostingView?.rootView = rootView
        }

        guard let panel else { return }

        let targetPoint = cursorPoint ?? NSEvent.mouseLocation
        if !panel.isVisible {
            panel.setFrameOrigin(originCentered(at: targetPoint))
            panel.orderFrontRegardless()
            // A non-activating panel can take key status without activating the app, so
            // Escape reaches this app's key monitor even while another app is in front.
            panel.makeKey()
        } else if recenterIfFar {
            let currentCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            let distance = hypot(targetPoint.x - currentCenter.x, targetPoint.y - currentCenter.y)
            if distance > 150 {
                panel.setFrameOrigin(originCentered(at: targetPoint))
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func containsScreenPoint(_ point: NSPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -16, dy: -16).contains(point)
    }

    private func originCentered(at point: NSPoint) -> NSPoint {
        var origin = NSPoint(
            x: point.x - panelSize.width / 2,
            y: point.y - panelSize.height / 2
        )

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - panelSize.width - 8)
            origin.y = min(max(origin.y, frame.minY + 8), frame.maxY - panelSize.height - 8)
        }
        return origin
    }
}

/// System-wide modifier, Escape, click and file-drag observation for the wheel.
/// `WheelSession` owns it for the life of the app, so no window has to be open for it to run.
@MainActor
final class ModifierKeyMonitor {
    private let onFlagsChanged: (NSEvent.ModifierFlags) -> Void
    /// File URLs of the system-wide drag in progress; called with `[]` when that drag ends.
    private let onDragPasteboardURLs: ([URL]) -> Void
    /// Returns `true` only when Escape was handled, so sheets and panels still receive it otherwise.
    private let onEscapePressed: () -> Bool
    private let onOutsideClick: (NSPoint) -> Void

    private var flags: NSEvent.ModifierFlags = []
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalFlagsMonitor: Any?
    private var globalMouseMonitor: Any?
    private var pollTimer: Timer?
    private var lastDragChangeCount: Int = 0
    private var isFileDragActive = false

    init(
        onFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
        onDragPasteboardURLs: @escaping ([URL]) -> Void,
        onEscapePressed: @escaping () -> Bool,
        onOutsideClick: @escaping (NSPoint) -> Void
    ) {
        self.onFlagsChanged = onFlagsChanged
        self.onDragPasteboardURLs = onDragPasteboardURLs
        self.onEscapePressed = onEscapePressed
        self.onOutsideClick = onOutsideClick
    }

    func start() {
        updateFlags(NSEvent.modifierFlags)
        // Whatever the last drag left on the pasteboard is not a drag in progress.
        lastDragChangeCount = NSPasteboard(name: .drag).changeCount

        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateFlags(event.modifierFlags)
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Escape is swallowed only when the wheel consumed it; otherwise sheets,
            // open panels and other windows must still see it.
            if event.keyCode == 53, self?.onEscapePressed() == true {
                return nil
            }
            return event
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.onOutsideClick(NSEvent.mouseLocation)
            return event
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.updateFlags(event.modifierFlags)
            }
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onOutsideClick(NSEvent.mouseLocation)
            }
        }

        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func updateFlags(_ newFlags: NSEvent.ModifierFlags) {
        guard newFlags != flags else { return }
        flags = newFlags
        onFlagsChanged(newFlags)
    }

    /// A file drag is in progress only while the left button is held AND the drag pasteboard
    /// changed since the button went down. A plain click, or a Shift/Command-click, never counts.
    private func pollState() {
        updateFlags(NSEvent.modifierFlags)

        let dragPasteboard = NSPasteboard(name: .drag)
        let isLeftMouseDown = (NSEvent.pressedMouseButtons & 1) != 0

        guard isLeftMouseDown else {
            lastDragChangeCount = dragPasteboard.changeCount
            if isFileDragActive {
                isFileDragActive = false
                onDragPasteboardURLs([])
            }
            return
        }

        guard dragPasteboard.changeCount != lastDragChangeCount else { return }
        lastDragChangeCount = dragPasteboard.changeCount

        let urls = (dragPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        if !urls.isEmpty || isFileDragActive {
            isFileDragActive = !urls.isEmpty
            onDragPasteboardURLs(urls)
        }
    }
}
