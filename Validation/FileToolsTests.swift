import AppKit
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import FileTools

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func image() throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
    return try #require(context.makeImage())
}

@Test func imageOrientationMetadataAndCollisions() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("photo.jpg")
    let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try image(), [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private"],
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N"]
    ] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let original = try Data(contentsOf: source)
    let loaded = try FileTools.readImage(source)
    #expect(loaded.image.width == 40 && loaded.image.height == 80)
    #expect(loaded.metadata.contains { $0.id.contains("GPS") })
    let output = try FileTools.exportImage(loaded.image, source: source, directory: folder)
    let repeated = try FileTools.exportImage(loaded.image, source: source, directory: folder)
    #expect(output != repeated)
    let cleaned = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(cleaned, 0, nil)) as NSDictionary
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    // ImageIO may generate technical EXIF fields when encoding PNG.
    // No source user comment, camera, date, GPS or other private field may survive.
    let exif = properties[kCGImagePropertyExifDictionary] as? [String: Any] ?? [:]
    #expect(Set(exif.keys).isSubset(of: ["ColorSpace", "PixelXDimension", "PixelYDimension"]))
    #expect(!properties.description.contains("private"))
    #expect(try Data(contentsOf: source) == original)
    #expect(try FileTools.readImage(output).image.width == 40)
}

@Test func cropValidationAndDimensions() throws {
    let input = try image()
    let cropped = try FileTools.croppedImage(input, rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    #expect(cropped.width == 40 && cropped.height == 20)
    for rect in [CGRect(x: -1, y: 0, width: 1, height: 1), CGRect.zero,
                 CGRect(x: 0.9, y: 0, width: 0.5, height: 1), CGRect(x: 0, y: 0, width: 0.001, height: 1)] {
        #expect(throws: FileToolError.self) { try FileTools.croppedImage(input, rect: rect) }
    }
}

@Test func multiframeImagesAreRejected() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("animated.gif")
    let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.gif.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(destination, try image(), nil)
    CGImageDestinationAddImage(destination, try image(), nil)
    #expect(CGImageDestinationFinalize(destination))
    #expect(throws: FileToolError.self) { try FileTools.readImage(source) }
}

private func pdf(width: Int, at url: URL) throws {
    let document = PDFDocument()
    let page = try #require(PDFPage(image: NSImage(cgImage: try image(), size: NSSize(width: width, height: 100))))
    document.insert(page, at: 0)
    #expect(document.write(to: url))
}

@Test func pdfMergeSplitAndOriginals() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = folder.appendingPathComponent("first.pdf")
    let second = folder.appendingPathComponent("second.pdf")
    try pdf(width: 100, at: first)
    try pdf(width: 200, at: second)
    let original = try Data(contentsOf: first)
    let output = try FileTools.mergePDFs([second, first], directory: folder)
    let merged = try FileTools.readPDF(output)
    #expect(merged.pageCount == 2)
    let firstWidth = try #require(merged.page(at: 0)).bounds(for: .mediaBox).width
    let secondWidth = try #require(merged.page(at: 1)).bounds(for: .mediaBox).width
    #expect(firstWidth > secondWidth)
    let pages = try FileTools.splitPDF(output, pages: 1...2, directory: folder)
    #expect(try FileTools.pageCount(pages.appendingPathComponent("Page-1.pdf")) == 1)
    #expect(try FileTools.pageCount(pages.appendingPathComponent("Page-2.pdf")) == 1)
    let again = try FileTools.splitPDF(output, pages: 2...2, directory: folder)
    #expect(pages != again)
    #expect(!FileManager.default.fileExists(atPath: again.appendingPathComponent("Page-1.pdf").path))
    #expect(throws: FileToolError.self) { try FileTools.splitPDF(first, pages: 1...2, directory: folder) }
    #expect(throws: FileToolError.self) { try FileTools.mergePDFs([first], directory: folder) }
    #expect(try Data(contentsOf: first) == original)
    let remaining = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(!remaining.contains { $0.hasPrefix(".mandarin-") })
}

@Test func failedMergeLeavesNoOutput() throws {
    let folder = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let valid = folder.appendingPathComponent("valid.pdf")
    let broken = folder.appendingPathComponent("broken.pdf")
    try pdf(width: 100, at: valid)
    try Data("invalid".utf8).write(to: broken)
    #expect(throws: FileToolError.self) { try FileTools.mergePDFs([valid, broken], directory: folder) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
}
