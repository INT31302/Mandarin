import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// App-lifetime owner of the radial wheel: input monitoring, wheel state and the file list.
/// It lives on the app delegate instead of inside a window, so closing the main window
/// neither stops the wheel from opening nor discards the files already added.
@MainActor
@Observable
final class WheelSession {
    let store = ConversionStore()

    private(set) var modifierFlags: NSEvent.ModifierFlags = []
    private(set) var latchedMode: DragMode = .none
    private(set) var isWheelVisible = false
    private(set) var draggedURLs: [URL] = []

    @ObservationIgnored private var monitor: ModifierKeyMonitor?
    @ObservationIgnored private var toolWindows: [FileToolWindowController] = []

    /// Starts system-wide monitoring. Called once at launch; repeated calls are ignored.
    func start() {
        guard monitor == nil else { return }
        let monitor = ModifierKeyMonitor(
            onFlagsChanged: { [weak self] flags in
                self?.modifierFlagsChanged(flags)
            },
            onDragPasteboardURLs: { [weak self] urls in
                self?.draggedURLs = urls
            },
            onEscapePressed: { [weak self] in
                self?.handleEscape() ?? false
            },
            onOutsideClick: { [weak self] screenPoint in
                self?.handleClick(at: screenPoint)
            }
        )
        monitor.start()
        self.monitor = monitor
    }

    // MARK: - Wheel contents

    var activeMode: DragMode {
        let liveMode = DragMode(flags: modifierFlags)
        return liveMode != .none ? liveMode : latchedMode
    }

    /// The file the wheel is built for. A file being dragged wins over the selection,
    /// because a drop on a sector applies that sector to the dragged file.
    var activePreviewJob: ConversionJob? {
        if let firstDragged = draggedURLs.first {
            return ConversionJob(sourceURL: firstDragged)
        }
        return store.selectedJob
    }

    var wheelItems: [WheelItem] {
        switch activeMode {
        case .none:
            return [
                WheelItem(id: "shift", title: "Shift", symbolName: "shift", isEnabled: true),
                WheelItem(id: "command", title: "Command", symbolName: "command", isEnabled: true),
                WheelItem(id: "control", title: "Control", symbolName: "control", isEnabled: true)
            ]
        case .shift:
            if let job = activePreviewJob {
                return job.availableFormats.map {
                    WheelItem(id: $0.id, title: $0.title, symbolName: $0.symbolName, isEnabled: true)
                }
            }
            return previewFormats
        case .command:
            return toolItems
        case .control:
            return actionItems
        }
    }

    private var previewFormats: [WheelItem] {
        SupportedFormat.allCases.filter(\.canWriteOnThisMac).map {
            WheelItem(id: $0.id, title: $0.title, symbolName: $0.symbolName, isEnabled: true)
        }
    }

    private var toolItems: [WheelItem] {
        let job = activePreviewJob
        let hasJob = job != nil
        let isImage = job?.category == .image
        return [
            WheelItem(id: "compress", title: "Compress", symbolName: "arrow.down.right.and.arrow.up.left", isEnabled: hasJob),
            WheelItem(id: "metadata", title: "Metadata", symbolName: "info.circle", isEnabled: isImage),
            WheelItem(id: "crop", title: "Crop", symbolName: "crop", isEnabled: isImage),
            WheelItem(id: "pdf", title: "Make PDF", symbolName: "doc.richtext", isEnabled: isImage),
            WheelItem(id: "mergePDF", title: "Merge PDF", symbolName: "doc.on.doc", isEnabled: job?.category == .pdf),
            WheelItem(id: "splitPDF", title: "Split PDF", symbolName: "scissors", isEnabled: job?.category == .pdf)
        ]
    }

    private var actionItems: [WheelItem] {
        let hasJob = activePreviewJob != nil
        return [
            WheelItem(id: "copy", title: "Copy", symbolName: "doc.on.doc", isEnabled: hasJob),
            WheelItem(id: "move", title: "Move", symbolName: "arrow.right.doc.on.clipboard", isEnabled: hasJob),
            WheelItem(id: "path", title: "Copy path", symbolName: "link", isEnabled: hasJob),
            WheelItem(id: "finder", title: "Finder", symbolName: "folder", isEnabled: hasJob)
        ]
    }

    // MARK: - Showing and hiding

    /// Modifier keys are read system-wide, so a modifier alone must not open the wheel over
    /// other apps: only a file drag in progress, an already-open wheel, or this app in front.
    private var shouldOpenWheelForModifier: Bool {
        // Editing shortcuts belong to the editor, rather than reopening the drag wheel.
        if toolWindows.contains(where: { $0.window?.isKeyWindow == true }) { return false }
        if !draggedURLs.isEmpty || FloatingWheelController.shared.isVisible {
            return true
        }
        return NSApp.isActive && (store.isDropTargeted || store.selectedJob != nil)
    }

    func presentWheelAtCursor(mode: DragMode, recenterIfFar: Bool = true) {
        latchedMode = mode
        isWheelVisible = true
        // The panel content observes this session, so later state changes redraw it on their own.
        FloatingWheelController.shared.show(at: NSEvent.mouseLocation, recenterIfFar: recenterIfFar) {
            WheelPanelContent(session: self)
        }
    }

    func dismissWheel() {
        isWheelVisible = false
        latchedMode = .none
        draggedURLs.removeAll()
        FloatingWheelController.shared.hide()
    }

    private func modifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        modifierFlags = flags
        let mode = DragMode(flags: flags)
        if mode != .none, shouldOpenWheelForModifier {
            presentWheelAtCursor(mode: mode)
        }
    }

    private func handleEscape() -> Bool {
        guard FloatingWheelController.shared.isVisible else { return false }
        dismissWheel()
        return true
    }

    private func handleClick(at screenPoint: NSPoint) {
        if FloatingWheelController.shared.isVisible,
           !FloatingWheelController.shared.containsScreenPoint(screenPoint) {
            dismissWheel()
        }
    }

    // MARK: - Window actions

    func selectJob(_ job: ConversionJob) {
        store.selectedJobID = job.id
        presentWheelAtCursor(mode: .shift)
    }

    func openWheelForSelection() {
        presentWheelAtCursor(mode: latchedMode == .none ? .shift : latchedMode)
    }

    func clearAll() {
        store.reset()
        dismissWheel()
    }

    /// Files dropped on the main window: add them, then open the wheel for the first one.
    func handleWindowDrop(_ providers: [NSItemProvider]) {
        FileURLLoader.load(from: providers) { [weak self] urls in
            guard let self else { return }
            self.addAndSelect(urls)
            let targetMode = self.activeMode == .none ? .shift : self.activeMode
            self.presentWheelAtCursor(mode: targetMode)
        }
    }

    // MARK: - Wheel actions

    func handleWheelDrop(urls: [URL], droppedItem: WheelItem?) {
        addAndSelect(urls)
        draggedURLs.removeAll()

        if let droppedItem {
            handleSelection(droppedItem)
        } else if latchedMode == .none {
            latchedMode = .shift
        }
    }

    func handleSelection(_ item: WheelItem) {
        guard item.isEnabled else { return }
        switch item.id {
        case "shift":
            latchedMode = .shift
            return
        case "command":
            latchedMode = .command
            return
        case "control":
            latchedMode = .control
            return
        default:
            break
        }

        guard let job = store.selectedJob else { return }

        if activeMode == .shift,
           let format = SupportedFormat(rawValue: item.id) {
            store.choose(format)
            dismissWheel()
            return
        }

        switch item.id {
        case "metadata", "crop", "mergePDF", "splitPDF":
            guard let kind = FileToolKind(rawValue: item.id),
                  (job.category == .image && (kind == .metadata || kind == .crop))
                    || (job.category == .pdf && (kind == .mergePDF || kind == .splitPDF)) else { return }
            dismissWheel()
            toolWindows.removeAll { $0.window?.isVisible != true }
            let controller = FileToolWindowController(kind: kind, source: job.sourceURL) { [weak self] output in
                guard let self, let index = self.store.jobs.firstIndex(where: { $0.id == job.id }) else { return }
                self.store.jobs[index].outputURL = output
                self.store.jobs[index].progress = 1
                self.store.jobs[index].state = .completed
            }
            toolWindows.append(controller)
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        case "compress":
            store.compressSelected()
            dismissWheel()
        case "pdf":
            store.makePDFSelected()
            dismissWheel()
        case "copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([job.sourceURL as NSURL])
            dismissWheel()
        case "move":
            dismissWheel()
            store.moveSelected()
        case "path":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(job.sourceURL.path, forType: .string)
            dismissWheel()
        case "finder":
            NSWorkspace.shared.activateFileViewerSelecting([job.sourceURL])
            dismissWheel()
        default:
            break
        }
    }

    /// Adds the files and selects the first one: the wheel previewed the first dragged file,
    /// so that is the one a sector applies to.
    private func addAndSelect(_ urls: [URL]) {
        store.add(urls: urls)
        if let firstURL = urls.first,
           let match = store.jobs.last(where: { $0.sourceURL == firstURL }) {
            store.selectedJobID = match.id
        }
    }
}

/// The floating panel's root view. Reading the session here (not in a captured snapshot)
/// keeps the wheel in step with modifier, drag and selection changes.
private struct WheelPanelContent: View {
    let session: WheelSession

    var body: some View {
        FormatWheelView(
            items: session.wheelItems,
            mode: session.activeMode,
            fileName: session.activePreviewJob?.sourceURL.lastPathComponent,
            onSelect: { item in
                session.handleSelection(item)
            },
            onDropFiles: { urls, droppedItem in
                session.handleWheelDrop(urls: urls, droppedItem: droppedItem)
            },
            onDismiss: {
                session.dismissWheel()
            }
        )
    }
}

enum FileURLLoader {
    /// Loads dropped file URLs in provider order, which matches the drag pasteboard, rather
    /// than in whichever order the loads finish. `completion` runs on the main queue.
    static func load(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var loaded = [URL?](repeating: nil, count: providers.count)

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock()
                loaded[index] = url
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let urls = loaded.compactMap { $0 }
            guard !urls.isEmpty else { return }
            completion(urls)
        }
    }
}
