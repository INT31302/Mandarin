import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FormatWheelView: View {
    let items: [WheelItem]
    let mode: DragMode
    var fileName: String? = nil
    let onSelect: (WheelItem) -> Void
    var onDropFiles: (([URL], WheelItem?) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var hoveredItemID: String?

    private let wheelSize: CGFloat = 320
    private let tangerine = Color(red: 1, green: 0.32, blue: 0)

    var body: some View {
        ZStack {
            // A single glass rind surrounds the rounded citrus segments.
            Circle()
                .fill(.clear)
                .frame(width: 298, height: 298)
                .glassEffect(.regular, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
                .allowsHitTesting(false)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                sectorButton(item, index: index)
            }

            VStack(spacing: 7) {
                Text(hoveredItem?.title ?? mode.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(.white.opacity(0.85), in: Capsule())
                    .shadow(color: .black.opacity(0.05), radius: 5, y: 3)

                if let fileName {
                    Text(fileName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(10)
            .frame(width: 100, height: 100)
            .background(.white.opacity(0.52), in: Circle())
            .contentShape(Circle())
            .onTapGesture { onDismiss?() }
            .accessibilityLabel(hoveredItem?.title ?? mode.title)
            .accessibilityHint("Click to close the menu")
        }
        .frame(width: wheelSize, height: wheelSize)
        .environment(\.colorScheme, .light)
        .contentShape(Circle())
        .onDrop(
            of: [UTType.fileURL],
            delegate: WheelDropDelegate(
                items: items,
                wheelSize: wheelSize,
                hoveredItemID: $hoveredItemID,
                onDropFiles: onDropFiles
            )
        )
    }

    private var hoveredItem: WheelItem? {
        items.first { $0.id == hoveredItemID && $0.isEnabled }
    }

    private func sectorButton(_ item: WheelItem, index: Int) -> some View {
        let shape = WheelSector(index: index, count: items.count)
        let isHovered = hoveredItemID == item.id && item.isEnabled
        let angle = Double(index) / Double(max(items.count, 1)) * 2 * .pi - .pi / 2
        let labelWidth: CGFloat = items.count > 8 ? 46 : 66

        return Button {
            onSelect(item)
        } label: {
            ZStack {
                shape.fill(
                    isHovered
                        ? AnyShapeStyle(tangerine)
                        : AnyShapeStyle(RadialGradient(
                            colors: [.white.opacity(0.78), Color(red: 0.86, green: 0.89, blue: 0.90).opacity(0.45)],
                            center: .center,
                            startRadius: 65,
                            endRadius: 150
                        ))
                )
                shape.stroke(isHovered ? tangerine : Color.gray.opacity(0.26), lineWidth: 0.75)

                VStack(spacing: 5) {
                    if mode != .shift {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 17, weight: .medium))
                    }
                    Text(mode == .shift ? item.title : item.title.uppercased())
                        .font(.system(size: mode == .shift ? 15 : 9, weight: .semibold))
                        .tracking(mode == .shift ? 0 : 0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(isHovered ? Color.white : Color.black.opacity(item.isEnabled ? 0.9 : 0.28))
                .frame(width: labelWidth)
                .offset(x: cos(angle) * 103, y: sin(angle) * 103)
            }
            .frame(width: wheelSize, height: wheelSize)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering && item.isEnabled {
                    hoveredItemID = item.id
                } else if hoveredItemID == item.id {
                    hoveredItemID = nil
                }
            }
        }
        .accessibilityLabel("\(item.title), \(mode.title)")
    }
}

/// The same rounded segment path is used for rendering, clicks, and file drops.
struct WheelSector: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let scale = min(rect.width, rect.height) / 320
        let outer: CGFloat = 142 * scale
        let inner: CGFloat = 57 * scale
        let corner: CGFloat = min(11, 100 / CGFloat(count)) * scale
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let middle = Double(index) / Double(count) * 2 * .pi - .pi / 2
        let half = .pi / Double(count) - 0.018
        let start = middle - half
        let end = middle + half
        let outerInset = Double(corner / outer)
        let innerInset = Double(corner / inner)

        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        var path = Path()
        path.move(to: point(outer, start + outerInset))
        path.addArc(center: center, radius: outer, startAngle: .radians(start + outerInset), endAngle: .radians(end - outerInset), clockwise: false)
        path.addQuadCurve(to: point(outer - corner, end), control: point(outer, end))
        path.addLine(to: point(inner + corner, end))
        path.addQuadCurve(to: point(inner, end - innerInset), control: point(inner, end))
        path.addArc(center: center, radius: inner, startAngle: .radians(end - innerInset), endAngle: .radians(start + innerInset), clockwise: true)
        path.addQuadCurve(to: point(inner + corner, start), control: point(inner, start))
        path.addLine(to: point(outer - corner, start))
        path.addQuadCurve(to: point(outer, start + outerInset), control: point(outer, start))
        path.closeSubpath()
        return path
    }
}

private struct WheelDropDelegate: DropDelegate {
    let items: [WheelItem]
    let wheelSize: CGFloat
    @Binding var hoveredItemID: String?
    let onDropFiles: (([URL], WheelItem?) -> Void)?

    func dropEntered(info: DropInfo) {
        updateHoveredItem(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateHoveredItem(at: info.location)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        withAnimation(.snappy(duration: 0.15)) {
            hoveredItemID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let targetItem = item(at: info.location)
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }

        hoveredItemID = nil
        // Provider order is kept, so the first URL is the dragged file the wheel previewed.
        FileURLLoader.load(from: providers) { urls in
            onDropFiles?(urls, targetItem)
        }
        return true
    }

    private func updateHoveredItem(at location: CGPoint) {
        let matched = item(at: location)
        if hoveredItemID != matched?.id {
            withAnimation(.snappy(duration: 0.14)) {
                hoveredItemID = matched?.id
            }
        }
    }

    private func item(at location: CGPoint) -> WheelItem? {
        let bounds = CGRect(x: 0, y: 0, width: wheelSize, height: wheelSize)
        return items.enumerated().first { index, candidate in
            candidate.isEnabled && WheelSector(index: index, count: items.count)
                .path(in: bounds).contains(location)
        }?.element
    }
}
