import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum FileCategory: String, CaseIterable, Identifiable, Sendable {
    case image
    case video
    case audio
    case pdf
    case unsupported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .image: "Images"
        case .video: "Video"
        case .audio: "Audio"
        case .pdf: "PDF"
        case .unsupported: "Unsupported"
        }
    }
}

nonisolated enum SupportedFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case png
    case jpeg
    case heic
    case tiff
    case webp
    case mov
    case mp4
    case m4a
    case wav
    case aiff
    case pdf

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var title: String {
        rawValue.uppercased()
    }

    var symbolName: String {
        switch self {
        case .png, .jpeg, .heic, .tiff, .webp: "photo"
        case .mov, .mp4: "film"
        case .m4a, .wav, .aiff: "waveform"
        case .pdf: "doc.richtext"
        }
    }

    var category: FileCategory {
        switch self {
        case .png, .jpeg, .heic, .tiff, .webp: .image
        case .mov, .mp4: .video
        case .m4a, .wav, .aiff: .audio
        case .pdf: .pdf
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .webp: .webP
        case .mov: .quickTimeMovie
        case .mp4: .mpeg4Movie
        case .m4a: .mpeg4Audio
        case .wav: .wav
        case .aiff: .aiff
        case .pdf: .pdf
        }
    }

    /// Whether this Mac can write the format. ImageIO decodes more image types than it encodes
    /// (WebP is read-only on macOS 27), so image outputs are checked against the system's encoders.
    var canWriteOnThisMac: Bool {
        switch category {
        case .image: Self.writableImageTypeIdentifiers.contains(contentType.identifier)
        case .video, .audio, .pdf, .unsupported: true
        }
    }

    private static let writableImageTypeIdentifiers: Set<String> =
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])

    static func formats(for sourceCategory: FileCategory) -> [SupportedFormat] {
        let candidates: [SupportedFormat] = switch sourceCategory {
        case .image: [.png, .jpeg, .heic, .tiff, .webp, .pdf]
        case .video: [.mov, .mp4, .m4a, .wav, .aiff]
        case .audio: [.m4a, .wav, .aiff]
        case .pdf: [.png, .jpeg, .heic, .tiff]
        case .unsupported: []
        }
        return candidates.filter(\.canWriteOnThisMac)
    }
}

nonisolated struct FileTypeDetector {
    static func contentType(for url: URL) -> UTType? {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            return type
        }
        return UTType(filenameExtension: url.pathExtension)
    }

    static func category(for url: URL) -> FileCategory {
        let type = contentType(for: url)
        if type?.conforms(to: .pdf) == true { return .pdf }
        if type?.conforms(to: .image) == true { return .image }
        if type?.conforms(to: .movie) == true { return .video }
        if type?.conforms(to: .audio) == true { return .audio }

        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tif", "tiff", "webp": return .image
        case "mov", "mp4", "m4v": return .video
        case "m4a", "wav", "aif", "aiff": return .audio
        case "pdf": return .pdf
        default: return .unsupported
        }
    }
}

nonisolated enum ConversionState: Equatable, Sendable {
    case queued
    case converting
    case completed
    case failed(String)

    var title: String {
        switch self {
        case .queued: "Ready"
        case .converting: "Converting"
        case .completed: "Complete"
        case .failed(let message): message
        }
    }
}

nonisolated struct ConversionJob: Identifiable, Sendable {
    let id: UUID
    var sourceURL: URL
    let category: FileCategory
    var selectedFormat: SupportedFormat?
    var progress: Double
    var state: ConversionState
    var outputURL: URL?

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.category = FileTypeDetector.category(for: sourceURL)
        self.selectedFormat = nil
        self.progress = 0
        self.state = .queued
        self.outputURL = nil
    }

    var availableFormats: [SupportedFormat] {
        let sourceType = FileTypeDetector.contentType(for: sourceURL)
        let sourceExt = sourceURL.pathExtension.lowercased()

        return SupportedFormat.formats(for: category).filter { format in
            if let sourceType, sourceType == format.contentType {
                return false
            }
            return format.fileExtension.lowercased() != sourceExt
        }
    }

    var displayName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }

    var fileSizeDescription: String {
        let bytes = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
