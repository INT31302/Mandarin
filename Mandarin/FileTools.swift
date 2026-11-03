import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

nonisolated enum FileToolError: LocalizedError {
    case invalidImage
    case animatedImage
    case invalidCrop
    case invalidPDF
    case invalidPages
    case needsMoreFiles
    case unableToWriteOutput

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The image could not be read."
        case .animatedImage: "This tool supports single-frame images. Animated and multi-page images are not flattened."
        case .invalidCrop: "Choose a crop inside the image that is at least one pixel wide and high."
        case .invalidPDF: "The PDF is empty, locked, damaged, or does not allow copying."
        case .invalidPages: "Choose a valid page range within the PDF."
        case .needsMoreFiles: "Choose at least two PDFs to merge."
        case .unableToWriteOutput: "The output file could not be written."
        }
    }
}

nonisolated struct MetadataEntry: Identifiable, Sendable {
    let id: String
    let value: String
}

nonisolated struct ImageToolSource: @unchecked Sendable {
    let image: CGImage
    let metadata: [MetadataEntry]
}

/// All processing happens away from the UI. Output is encoded in memory and written
/// exclusively, so a failed operation cannot leave a partial or overwrite an existing file.
nonisolated enum FileTools {
    static func readImage(_ url: URL) throws -> ImageToolSource {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            throw FileToolError.invalidImage
        }
        guard CGImageSourceGetCount(source) == 1 else { throw FileToolError.animatedImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileToolError.invalidImage
        }
        var entries: [MetadataEntry] = []
        func flatten(_ dictionary: [String: Any], prefix: String = "") {
            for key in dictionary.keys.sorted() {
                guard let value = dictionary[key] else { continue }
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                if let child = value as? [String: Any] {
                    flatten(child, prefix: path)
                } else {
                    entries.append(MetadataEntry(id: path, value: String(describing: value)))
                }
            }
        }
        flatten(properties)
        return ImageToolSource(image: image, metadata: entries)
    }

    /// Normalized coordinates use the displayed, oriented image's top-left origin.
    static func croppedImage(_ image: CGImage, rect: CGRect) throws -> CGImage {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.minX >= 0, rect.minY >= 0, rect.maxX <= 1.000001, rect.maxY <= 1.000001,
              rect.width > 0, rect.height > 0 else { throw FileToolError.invalidCrop }
        let pixelRect = CGRect(
            x: floor(rect.minX * Double(image.width)),
            y: floor(rect.minY * Double(image.height)),
            width: floor(rect.width * Double(image.width)),
            height: floor(rect.height * Double(image.height))
        )
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = image.cropping(to: pixelRect) else { throw FileToolError.invalidCrop }
        return cropped
    }

    static func exportImage(_ image: CGImage, source: URL, directory: URL, crop: CGRect? = nil) throws -> URL {
        let outputImage = try crop.map { try croppedImage(image, rect: $0) } ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw FileToolError.unableToWriteOutput
        }
        // Add decoded pixels, never source metadata or embedded thumbnails.
        // PNG retains necessary color information but excludes source EXIF/IPTC/GPS.
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw FileToolError.unableToWriteOutput }
        return try writeUnique(data as Data, source: source, directory: directory,
                               tag: crop == nil ? "clean" : "cropped", extension: "png")
    }

    static func readPDF(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url), !document.isLocked,
              document.allowsCopying, document.pageCount > 0 else { throw FileToolError.invalidPDF }
        return document
    }

    static func pageCount(_ url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try readPDF(url).pageCount
    }

    static func mergePDFs(_ urls: [URL], directory: URL) throws -> URL {
        guard urls.count >= 2, let first = urls.first else { throw FileToolError.needsMoreFiles }
        let result = PDFDocument()
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let document = try readPDF(url)
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index)?.copy() as? PDFPage else { throw FileToolError.invalidPDF }
                result.insert(page, at: result.pageCount)
            }
        }
        guard let data = result.dataRepresentation() else { throw FileToolError.unableToWriteOutput }
        return try writeUnique(data, source: first, directory: directory, tag: "merged", extension: "pdf")
    }

    static func splitPDF(_ url: URL, pages: ClosedRange<Int>, directory: URL) throws -> URL {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let document = try readPDF(url)
        guard pages.lowerBound >= 1, pages.upperBound <= document.pageCount else { throw FileToolError.invalidPages }
        let staging = directory.appendingPathComponent(".mandarin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        for number in pages {
            let single = PDFDocument()
            guard let page = document.page(at: number - 1)?.copy() as? PDFPage else { throw FileToolError.invalidPDF }
            single.insert(page, at: 0)
            guard let data = single.dataRepresentation() else { throw FileToolError.unableToWriteOutput }
            try data.write(to: staging.appendingPathComponent("Page-\(number).pdf"), options: .withoutOverwriting)
        }
        let base = url.deletingPathExtension().lastPathComponent + "-pages"
        for suffix in 1...10_000 {
            let folder = directory.appendingPathComponent(suffix == 1 ? base : "\(base)-\(suffix)", isDirectory: true)
            do {
                try FileManager.default.moveItem(at: staging, to: folder)
                return folder
            } catch {
                if !FileManager.default.fileExists(atPath: folder.path) { throw error }
            }
        }
        throw FileToolError.unableToWriteOutput
    }

    private static func writeUnique(_ data: Data, source: URL, directory: URL, tag: String, extension ext: String) throws -> URL {
        let access = directory.startAccessingSecurityScopedResource()
        defer { if access { directory.stopAccessingSecurityScopedResource() } }
        let staging = directory.appendingPathComponent(".mandarin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let stagedFile = staging.appendingPathComponent("output")
        try data.write(to: stagedFile, options: .atomic)
        let base = source.deletingPathExtension().lastPathComponent + "-" + tag
        for suffix in 1...10_000 {
            let name = suffix == 1 ? base : "\(base)-\(suffix)"
            let url = directory.appendingPathComponent("\(name).\(ext)")
            do {
                try FileManager.default.moveItem(at: stagedFile, to: url)
                return url
            } catch CocoaError.fileWriteFileExists {
                continue
            }
        }
        throw FileToolError.unableToWriteOutput
    }
}
