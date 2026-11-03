import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Observation
import PDFKit
import UniformTypeIdentifiers

nonisolated enum ConversionError: LocalizedError, Sendable {
    case unsupportedFormat
    case unableToReadSource
    case unableToWriteOutput
    case mediaExportFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "This conversion is not supported yet."
        case .unableToReadSource: "The source file could not be opened."
        case .unableToWriteOutput: "The converted file could not be written."
        case .mediaExportFailed: "The media export failed."
        }
    }
}

nonisolated struct OutputNamer {
    static func uniqueURL(
        for sourceURL: URL,
        format: SupportedFormat,
        in directory: URL? = nil,
        suffixTag: String? = nil
    ) -> URL {
        let folder = directory ?? sourceURL.deletingLastPathComponent()
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let base = suffixTag.map { "\(baseName)-\($0)" } ?? baseName
        var candidate = folder.appendingPathComponent("\(base).\(format.fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(suffix).\(format.fileExtension)")
            suffix += 1
        }
        return candidate
    }
}

nonisolated struct NativeConverter {
    static func convert(
        job: ConversionJob,
        to destination: URL,
        quality: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let format = job.selectedFormat else { throw ConversionError.unsupportedFormat }

        switch format.category {
        case .image:
            try await Task.detached(priority: .userInitiated) {
                try convertImage(from: job.sourceURL, sourceCategory: job.category, to: destination, format: format, quality: quality)
            }.value
            progress(1)
        case .video, .audio:
            try await convertMedia(from: job.sourceURL, to: destination, format: format, progress: progress)
        case .pdf:
            try await Task.detached(priority: .userInitiated) {
                try convertPDF(from: job.sourceURL, sourceCategory: job.category, to: destination)
            }.value
            progress(1)
        case .unsupported:
            throw ConversionError.unsupportedFormat
        }

        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw ConversionError.unableToWriteOutput
        }
        return destination
    }

    private static func loadCGImage(from source: URL, sourceCategory: FileCategory) -> CGImage? {
        if sourceCategory == .pdf {
            guard let document = PDFDocument(url: source),
                  let page = document.page(at: 0) else {
                return nil
            }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0
            let width = max(Int(bounds.width * scale), 1)
            let height = max(Int(bounds.height * scale), 1)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            return context.makeImage()
        }

        if let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            return cgImage
        }

        guard let image = NSImage(contentsOf: source) else { return nil }
        var proposedRect = NSRect.zero
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func convertImage(
        from source: URL,
        sourceCategory: FileCategory,
        to destination: URL,
        format: SupportedFormat,
        quality: Double
    ) throws {
        guard format.canWriteOnThisMac else {
            throw ConversionError.unsupportedFormat
        }
        guard let cgImage = loadCGImage(from: source, sourceCategory: sourceCategory) else {
            throw ConversionError.unableToReadSource
        }
        guard let destinationRef = CGImageDestinationCreateWithURL(
            destination as CFURL,
            format.contentType.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.unableToWriteOutput
        }

        let normalizedQuality = min(max(quality, 0.1), 1.0)
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: normalizedQuality
        ]
        CGImageDestinationAddImage(destinationRef, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destinationRef) else {
            throw ConversionError.unableToWriteOutput
        }
    }

    private static func convertMedia(
        from source: URL,
        to destination: URL,
        format: SupportedFormat,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        switch format {
        case .mov, .mp4, .m4a:
            let asset = AVURLAsset(url: source)
            let preset = (format == .m4a) ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                throw ConversionError.mediaExportFailed
            }

            let outputType: AVFileType = switch format {
            case .mov: .mov
            case .mp4: .mp4
            case .m4a: .m4a
            default: .mp4
            }

            try await session.export(to: destination, as: outputType)
            progress(1)

        case .wav, .aiff:
            try await convertLinearPCMAudio(from: source, to: destination, format: format, progress: progress)

        default:
            throw ConversionError.unsupportedFormat
        }
    }

    private static func convertLinearPCMAudio(
        from source: URL,
        to destination: URL,
        format: SupportedFormat,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks.first else {
            throw ConversionError.unableToReadSource
        }

        let durationSeconds = (try? await asset.load(.duration).seconds) ?? 0
        let reader = try AVAssetReader(asset: asset)

        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        guard reader.canAdd(readerOutput) else {
            throw ConversionError.mediaExportFailed
        }
        let provider = reader.outputProvider(for: readerOutput)

        let fileType: AVFileType = (format == .aiff) ? .aiff : .wav
        let writer = try AVAssetWriter(outputURL: destination, fileType: fileType)

        let writerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: format == .aiff,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerOutputSettings)
        guard writer.canAdd(writerInput) else {
            throw ConversionError.mediaExportFailed
        }
        let receiver = writer.inputReceiver(for: writerInput)

        do {
            try reader.start()
            try writer.start()
        } catch {
            throw ConversionError.mediaExportFailed
        }
        writer.startSession(atSourceTime: .zero)

        do {
            while let sampleBuffer = try await provider.next() {
                let pts = sampleBuffer.presentationTimeStamp.seconds
                if durationSeconds > 0, pts.isFinite {
                    progress(min(max(pts / durationSeconds, 0), 0.99))
                }
                try await receiver.append(sampleBuffer)
            }
            receiver.finish()
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw ConversionError.mediaExportFailed
        }

        await writer.finishWriting()
        if writer.status != .completed {
            throw ConversionError.unableToWriteOutput
        }
        progress(1)
    }

    private static func convertPDF(
        from source: URL,
        sourceCategory: FileCategory,
        to destination: URL
    ) throws {
        if sourceCategory == .image {
            guard let image = NSImage(contentsOf: source),
                  let page = PDFPage(image: image) else {
                throw ConversionError.unableToReadSource
            }
            let document = PDFDocument()
            document.insert(page, at: 0)
            guard document.write(to: destination) else {
                throw ConversionError.unableToWriteOutput
            }
            return
        }

        guard let document = PDFDocument(url: source) else {
            throw ConversionError.unableToReadSource
        }
        guard document.write(to: destination) else {
            throw ConversionError.unableToWriteOutput
        }
    }
}

@MainActor
@Observable
final class ConversionStore {
    var jobs: [ConversionJob] = []
    var selectedJobID: UUID?
    var isDropTargeted = false
    var isRunning = false
    var lastError: String?

    var selectedJob: ConversionJob? {
        guard let selectedJobID else { return nil }
        return jobs.first { $0.id == selectedJobID }
    }

    private var configuredQuality: Double {
        let stored = UserDefaults.standard.double(forKey: "defaultQuality")
        let percentage = stored > 0 ? stored : 88.0
        return percentage / 100.0
    }

    private var asksForOutputDirectory: Bool {
        UserDefaults.standard.string(forKey: "defaultOutputFolder") == "Ask each time"
    }

    func add(urls: [URL]) {
        let newJobs = urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(ConversionJob.init)
        guard !newJobs.isEmpty else { return }

        jobs.append(contentsOf: newJobs)
        if selectedJobID == nil || selectedJob?.state == .completed {
            selectedJobID = newJobs.first?.id
        }
        lastError = nil
    }

    func choose(_ format: SupportedFormat) {
        guard let selectedJobID,
              let selectedIndex = jobs.firstIndex(where: { $0.id == selectedJobID }) else { return }

        // The wheel can be built from another file than the one selected (a drag preview, a wheel
        // left open), so the format is checked against the file it is about to convert.
        guard jobs[selectedIndex].availableFormats.contains(format) else {
            lastError = "\(jobs[selectedIndex].sourceURL.lastPathComponent) can't be converted to \(format.title)."
            return
        }

        let category = jobs[selectedIndex].category
        var batchIDs = jobs.indices
            .filter {
                jobs[$0].category == category
                    && jobs[$0].state == .queued
                    && jobs[$0].availableFormats.contains(format)
            }
            .map { jobs[$0].id }

        if batchIDs.isEmpty {
            jobs[selectedIndex].state = .queued
            jobs[selectedIndex].outputURL = nil
            batchIDs = [selectedJobID]
        }

        let outputDirectory: URL?
        if asksForOutputDirectory {
            guard let chosenDirectory = promptForDirectory(
                title: "Choose Output Folder",
                defaultDirectory: jobs[selectedIndex].sourceURL.deletingLastPathComponent()
            ) else {
                return
            }
            outputDirectory = chosenDirectory
        } else {
            outputDirectory = nil
        }

        for index in jobs.indices where batchIDs.contains(jobs[index].id) {
            jobs[index].selectedFormat = format
        }

        Task {
            await startAll(jobIDs: batchIDs, outputDirectory: outputDirectory, quality: configuredQuality)
        }
    }

    func compressSelected() {
        guard let job = selectedJob else { return }
        let targetFormat: SupportedFormat = switch job.category {
        case .image: .jpeg
        case .video: .mp4
        case .audio: .m4a
        case .pdf: .pdf
        case .unsupported: .jpeg
        }

        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index].selectedFormat = targetFormat
        jobs[index].state = .queued

        let compressedQuality = min(configuredQuality * 0.72, 0.65)
        Task {
            await start(jobID: job.id, outputDirectory: nil, quality: compressedQuality, suffixTag: "compressed")
        }
    }

    func makePDFSelected() {
        guard let job = selectedJob, job.category == .image else { return }
        choose(.pdf)
    }

    func moveSelected() {
        guard let job = selectedJob,
              let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }

        guard let destinationFolder = promptForDirectory(
            title: "Move File To…",
            defaultDirectory: job.sourceURL.deletingLastPathComponent()
        ) else {
            return
        }

        let targetURL = destinationFolder.appendingPathComponent(job.sourceURL.lastPathComponent)
        guard targetURL != job.sourceURL else { return }

        do {
            try FileManager.default.moveItem(at: job.sourceURL, to: targetURL)
            jobs[index].sourceURL = targetURL
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func promptForDirectory(title: String, defaultDirectory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }

    func startAll(jobIDs: [UUID], outputDirectory: URL? = nil, quality: Double) async {
        for jobID in jobIDs {
            await start(jobID: jobID, outputDirectory: outputDirectory, quality: quality)
        }
    }

    func start(jobID: UUID, outputDirectory: URL? = nil, quality: Double, suffixTag: String? = nil) async {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }),
              let format = jobs[index].selectedFormat else { return }

        jobs[index].state = .converting
        jobs[index].progress = 0
        isRunning = true
        lastError = nil
        let job = jobs[index]
        let destination = OutputNamer.uniqueURL(
            for: job.sourceURL,
            format: format,
            in: outputDirectory,
            suffixTag: suffixTag
        )

        do {
            let outputURL = try await NativeConverter.convert(job: job, to: destination, quality: quality) { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.updateProgress(jobID: jobID, value: value)
                }
            }
            if let index = jobs.firstIndex(where: { $0.id == jobID }) {
                jobs[index].progress = 1
                jobs[index].outputURL = outputURL
                jobs[index].state = .completed
            }
        } catch {
            if let index = jobs.firstIndex(where: { $0.id == jobID }) {
                jobs[index].state = .failed(error.localizedDescription)
            }
            lastError = error.localizedDescription
        }
        isRunning = jobs.contains { $0.state == .converting }
    }

    func updateProgress(jobID: UUID, value: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[index].progress = value
    }

    func reset() {
        jobs.removeAll()
        selectedJobID = nil
        lastError = nil
        isRunning = false
    }
}
