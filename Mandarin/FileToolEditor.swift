import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileToolKind: String {
    case metadata, crop, mergePDF, splitPDF

    var title: String {
        switch self {
        case .metadata: "Image Metadata"
        case .crop: "Crop Image"
        case .mergePDF: "Merge PDFs"
        case .splitPDF: "Split PDF"
        }
    }
}

struct PDFInput: Identifiable {
    let id = UUID()
    let url: URL
}

/// An independent window also works when the main window has been closed.
@MainActor
final class FileToolWindowController: NSWindowController {
    init(kind: FileToolKind, source: URL, completion: @escaping (URL) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = kind.title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FileToolEditor(kind: kind, source: source, completion: completion))
        window.minSize = NSSize(width: 600, height: 520)
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { nil }
}

private struct FileToolEditor: View {
    let kind: FileToolKind
    let source: URL
    let completion: (URL) -> Void

    @State private var imageSource: ImageToolSource?
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var inputs: [PDFInput] = []
    @State private var pageCount = 0
    @State private var firstPage = 1
    @State private var lastPage = 1
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var output: URL?

    private var canSave: Bool {
        guard !isLoading, !isSaving else { return false }
        switch kind {
        case .metadata, .crop: return imageSource != nil
        case .mergePDF: return inputs.count >= 2
        case .splitPDF: return pageCount > 0 && firstPage >= 1 && lastPage >= firstPage && lastPage <= pageCount
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title).font(.title2.bold())
            Text(source.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(isSaving)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
            }
            if let output {
                HStack {
                    Label(output.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).lineLimit(1)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                }
            }
            Divider()
            HStack {
                Text("Saves a new copy. Your original files stay unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if isSaving { ProgressView().controlSize(.small) }
                Button("Export…", action: export)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 550, minHeight: 450)
        .task { await load() }
    }

    @ViewBuilder
    private var editor: some View {
        switch kind {
        case .metadata:
            if let imageSource {
                VStack(alignment: .leading) {
                    Text("Export a PNG without source personal metadata (GPS, camera details, comments or embedded thumbnails). Color and image dimensions are retained.")
                        .font(.callout)
                    List(imageSource.metadata) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.id).font(.caption.bold())
                            Text(entry.value).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        case .crop:
            if let imageSource {
                VStack {
                    CropCanvas(image: imageSource.image, selection: $crop)
                    HStack {
                        Text("\(Int(crop.width * Double(imageSource.image.width))) × \(Int(crop.height * Double(imageSource.image.height))) px")
                            .monospacedDigit()
                        Spacer()
                        Button("Reset") { crop = CGRect(x: 0, y: 0, width: 1, height: 1) }
                    }
                    Text("Drag on the image to select a crop. Export saves a PNG.")
                        .font(.caption).foregroundStyle(.secondary)
                    CropControls(selection: $crop)
                }
            }
        case .mergePDF:
            VStack(alignment: .leading) {
                Text("Pages are merged in the file order below.")
                List {
                    ForEach(inputs) { input in
                        HStack {
                            Text(input.url.lastPathComponent).lineLimit(1)
                            Spacer()
                            Button { move(input.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                .accessibilityLabel("Move up")
                                .disabled(inputs.first?.id == input.id)
                            Button { move(input.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                .accessibilityLabel("Move down")
                                .disabled(inputs.last?.id == input.id)
                            Button { inputs.removeAll { $0.id == input.id } } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("Remove PDF")
                        }
                    }
                }
                Button("Add PDFs…", action: addPDFs)
            }
        case .splitPDF:
            VStack(alignment: .leading, spacing: 16) {
                Text("\(pageCount) pages")
                Text("Export each page in the selected range as a separate PDF in a new folder.")
                Stepper("First page: \(firstPage)", value: $firstPage, in: 1...max(pageCount, 1))
                Stepper("Last page: \(lastPage)", value: $lastPage, in: 1...max(pageCount, 1))
                if firstPage > lastPage {
                    Text("The last page must be at or after the first page.").foregroundStyle(.red)
                }
                Spacer()
            }
        }
    }

    private func load() async {
        do {
            switch kind {
            case .metadata, .crop:
                imageSource = try await Task.detached(priority: .userInitiated) { try FileTools.readImage(source) }.value
            case .mergePDF:
                _ = try await Task.detached { try FileTools.pageCount(source) }.value
                inputs = [PDFInput(url: source)]
            case .splitPDF:
                pageCount = try await Task.detached { try FileTools.pageCount(source) }.value
                lastPage = pageCount
            }
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func addPDFs() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            inputs.append(contentsOf: panel.urls.map { PDFInput(url: $0) })
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let index = inputs.firstIndex(where: { $0.id == id }),
              inputs.indices.contains(index + delta) else { return }
        inputs.swapAt(index, index + delta)
    }

    private func export() {
        guard canSave else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = source.deletingLastPathComponent()
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        let currentImage = imageSource
        let currentCrop = crop
        let urls = inputs.map(\.url)
        let pages = firstPage...max(firstPage, lastPage)
        isSaving = true
        errorMessage = nil
        output = nil
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let access = directory.startAccessingSecurityScopedResource()
                    defer { if access { directory.stopAccessingSecurityScopedResource() } }
                    switch kind {
                    case .metadata, .crop:
                        guard let currentImage else { throw FileToolError.invalidImage }
                        return try FileTools.exportImage(currentImage.image, source: source, directory: directory,
                                                         crop: kind == .crop ? currentCrop : nil)
                    case .mergePDF:
                        return try FileTools.mergePDFs(urls, directory: directory)
                    case .splitPDF:
                        return try FileTools.splitPDF(source, pages: pages, directory: directory)
                    }
                }.value
                output = result
                completion(result)
            } catch { errorMessage = error.localizedDescription }
            isSaving = false
        }
    }
}

private struct CropCanvas: View {
    let image: CGImage
    @Binding var selection: CGRect

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / CGFloat(image.width), geometry.size.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                Rectangle()
                    .fill(.black.opacity(0.2))
                    .frame(width: size.width, height: size.height)
                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .background(.orange.opacity(0.12))
                    .frame(width: selection.width * size.width, height: selection.height * size.height)
                    .offset(x: selection.minX * size.width, y: selection.minY * size.height)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard size.width > 0, size.height > 0 else { return }
                        let startX = min(max(value.startLocation.x / size.width, 0), 1)
                        let startY = min(max(value.startLocation.y / size.height, 0), 1)
                        let endX = min(max(value.location.x / size.width, 0), 1)
                        let endY = min(max(value.location.y / size.height, 0), 1)
                        selection = CGRect(x: min(startX, endX), y: min(startY, endY),
                                           width: abs(endX - startX), height: abs(endY - startY))
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Crop preview. Use the controls below to adjust the selection.")
        }
        .frame(minHeight: 160)
    }
}

private struct CropControls: View {
    @Binding var selection: CGRect

    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("Left")
                Slider(value: Binding(
                    get: { selection.minX },
                    set: { selection.origin.x = $0; selection.size.width = min(selection.width, 1 - $0) }
                ), in: 0...0.99).accessibilityLabel("Crop left")
                Text("Top")
                Slider(value: Binding(
                    get: { selection.minY },
                    set: { selection.origin.y = $0; selection.size.height = min(selection.height, 1 - $0) }
                ), in: 0...0.99).accessibilityLabel("Crop top")
            }
            GridRow {
                Text("Width")
                Slider(value: Binding(
                    get: { selection.width },
                    set: { selection.size.width = $0 }
                ), in: 0...max(1 - selection.minX, 0.001)).accessibilityLabel("Crop width")
                Text("Height")
                Slider(value: Binding(
                    get: { selection.height },
                    set: { selection.size.height = $0 }
                ), in: 0...max(1 - selection.minY, 0.001)).accessibilityLabel("Crop height")
            }
        }
    }
}
