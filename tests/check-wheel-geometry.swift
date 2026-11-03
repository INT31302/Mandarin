import SwiftUI

@main
struct WheelGeometryChecks {
    static func main() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 320)
        for count in [1, 2, 4, 6, 7, 11] {
            let paths = (0..<count).map { WheelSector(index: $0, count: count).path(in: bounds) }
            for index in 0..<count {
                let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
                for radius in [65.0, 103.0, 135.0] {
                    let point = CGPoint(x: 160 + cos(angle) * radius, y: 160 + sin(angle) * radius)
                    let hits = paths.indices.filter { paths[$0].contains(point) }
                    precondition(hits == [index], "Segment interior must select exactly its own item: count=\(count), index=\(index), radius=\(radius)")
                }
                let gapAngle = angle + .pi / Double(count)
                let gap = CGPoint(x: 160 + cos(gapAngle) * 103, y: 160 + sin(gapAngle) * 103)
                precondition(!paths.contains { $0.contains(gap) }, "Gaps must not select an adjacent action")
            }
            for point in [CGPoint(x: 160, y: 160), CGPoint(x: 160, y: 110), CGPoint(x: 160, y: 10)] {
                precondition(!paths.contains { $0.contains(point) }, "Hub and outside must not select an action")
            }
        }
        precondition(WheelSector(index: 0, count: 0).path(in: bounds).isEmpty)
        print("PASS: segment interiors, gaps, center, outside, and empty menus")
    }
}
