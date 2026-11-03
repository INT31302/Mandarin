import SwiftUI

struct DropZoneView: View {
    let hasFiles: Bool
    let isTargeted: Bool

    private let tangerine = Color(red: 0.94, green: 0.36, blue: 0.10)
    private let ink = Color(red: 0.28, green: 0.20, blue: 0.16)

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.on.doc.fill")
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(tangerine)
                .frame(width: 58, height: 58)
                .background(tangerine.opacity(isTargeted ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 18))

            Text(isTargeted ? "Release to choose a format" : (hasFiles ? "Drop more files" : "Drop files to begin"))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(ink)

            Text("Images, video, audio, and PDF stay on your Mac")
                .font(.subheadline)
                .foregroundStyle(ink.opacity(0.65))
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 170)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .light)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(red: 1, green: 0.96, blue: 0.90).opacity(isTargeted ? 0.8 : 0.55))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(isTargeted ? tangerine.opacity(0.8) : .white.opacity(0.8), lineWidth: isTargeted ? 2 : 1)
                }
                .shadow(color: tangerine.opacity(isTargeted ? 0.18 : 0.06), radius: 12, y: 4)
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.easeOut(duration: 0.18), value: isTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File drop area")
        .accessibilityHint("Drop files here to choose an output format")
    }
}
