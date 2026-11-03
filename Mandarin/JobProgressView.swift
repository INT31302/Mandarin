import AppKit
import SwiftUI

struct JobProgressView: View {
    let jobs: [ConversionJob]
    var selectedJobID: UUID? = nil
    var onSelectJob: ((ConversionJob) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent conversions")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(jobs.count) item\(jobs.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(jobs) { job in
                        let isSelected = job.id == selectedJobID
                        HStack(spacing: 12) {
                            Image(systemName: icon(for: job.category))
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)

                                Text(job.state.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if case .converting = job.state {
                                ProgressView(value: job.progress)
                                    .frame(width: 86)
                            } else if let outputURL = job.outputURL {
                                Button("Show") {
                                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Text(job.fileSizeDescription)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            .white.opacity(isSelected ? 0.72 : 0.5),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.orange.opacity(0.65), lineWidth: 1.5)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onTapGesture {
                            onSelectJob?(job)
                        }
                    }
                }
            }
            .frame(maxHeight: 165)
        }
    }

    private func icon(for category: FileCategory) -> String {
        switch category {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .pdf: "doc.richtext"
        case .unsupported: "questionmark.square"
        }
    }
}
