import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The main window. It only displays and drives `WheelSession`; the wheel, its input
/// monitoring and the file list belong to the session, so they outlive this window.
struct ContentView: View {
    @Environment(WheelSession.self) private var session
    @Environment(\.openSettings) private var openSettings

    private var store: ConversionStore { session.store }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.62, blue: 0.18),
                    Color(red: 0.92, green: 0.25, blue: 0.08),
                    Color(red: 0.52, green: 0.08, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.yellow.opacity(0.18))
                .blur(radius: 4)
                .frame(width: 220)
                .offset(x: 220, y: -190)

            VStack(spacing: 18) {
                header

                if let selectedJob = store.selectedJob {
                    selectedFilePanel(selectedJob)
                } else {
                    DropZoneView(hasFiles: !store.jobs.isEmpty, isTargeted: store.isDropTargeted)
                }

                modifierHintBar

                if !store.jobs.isEmpty {
                    JobProgressView(
                        jobs: store.jobs,
                        selectedJobID: store.selectedJobID,
                        onSelectJob: { job in
                            session.selectJob(job)
                        }
                    )
                }
            }
            .padding(28)
            .frame(minWidth: 500, minHeight: 430)
            .background(.ultraThinMaterial.opacity(0.38), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(18)
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: dropTargetBinding) { providers in
            session.handleWindowDrop(providers)
            return true
        }
    }

    private var dropTargetBinding: Binding<Bool> {
        Binding(
            get: { session.store.isDropTargeted },
            set: { session.store.isDropTargeted = $0 }
        )
    }

    private var modifierHintBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                modePill(title: "⇧ Shift • Convert", mode: .shift)
                modePill(title: "⌘ Cmd • Tools", mode: .command)
                modePill(title: "⌃ Ctrl • Actions", mode: .control)
            }

            Text("Hold a modifier key while dragging anywhere — the radial wheel pops up right at your mouse cursor.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private func modePill(title: String, mode: DragMode) -> some View {
        let isActive = session.isWheelVisible && session.activeMode == mode
        return Button {
            session.presentWheelAtCursor(mode: mode)
        } label: {
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isActive ? AnyShapeStyle(mode.accent.gradient) : AnyShapeStyle(.white.opacity(0.14)))
                )
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(isActive ? 0.6 : 0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mandarin")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(session.isWheelVisible ? session.activeMode.title : "Local file converter")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Button {
                openSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

            Button {
                session.clearAll()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear files")
            .disabled(store.jobs.isEmpty)
        }

        if let lastError = store.lastError {
            Label(lastError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.red.opacity(0.28), in: Capsule())
        }
    }

    private func selectedFilePanel(_ job: ConversionJob) -> some View {
        Button {
            session.openWheelForSelection()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon(for: job.category))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)

                Text(job.sourceURL.lastPathComponent)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Click or press Shift / Command / Control to open wheel at cursor")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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

#Preview {
    ContentView()
        .environment(WheelSession())
}
