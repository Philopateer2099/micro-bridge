import CoreGraphics

/// Moving the pointer between the parts of a window that scroll on their own (a chat, a web page,
/// a sidebar), so that the stick scrolls the one it lands in.
public enum Panes {
    /// A pane whose middle is closer than this sideways is in the same place, such as a browser
    /// tab hidden under the one on show.
    public static let sameColumn = 20.0

    /// The pane to the left (or right) of the one the pointer is in: the nearest by its middle,
    /// then the one level with the pointer, skipping any in the same place. With the pointer in no
    /// pane, the nearest that way from the pointer, else the largest. Nil at the window's edge.
    public static func next(from pointer: CGPoint, in panes: [CGRect], left: Bool) -> CGRect? {
        let current = panes.filter { $0.contains(pointer) }.min { area($0) < area($1) }
        let from = current?.midX ?? pointer.x
        let ahead = panes.filter { (left ? from - $0.midX : $0.midX - from) > sameColumn }
        if let nearest = ahead.min(by: { distance($0, from, pointer) < distance($1, from, pointer) }) {
            return nearest
        }
        return current == nil ? panes.max { area($0) < area($1) } : nil
    }

    /// Where the pointer goes in a pane: its middle.
    public static func spot(in pane: CGRect) -> CGPoint {
        CGPoint(x: pane.midX, y: pane.midY)
    }

    private static func area(_ pane: CGRect) -> Double {
        pane.width * pane.height
    }

    private static func distance(_ pane: CGRect, _ x: Double, _ pointer: CGPoint) -> (Double, Double) {
        let level = pane.minY <= pointer.y && pointer.y <= pane.maxY
        return (abs(pane.midX - x), level ? 0 : abs(pane.midY - pointer.y))
    }
}
