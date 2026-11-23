import CoreGraphics

/// Moving the pointer between the parts of a window that scroll on their own (a chat, a web page,
/// a sidebar), so that the stick scrolls the one it lands in.
public enum Panes {
    /// A pane whose middle is closer than this sideways is in the same place, such as a browser
    /// tab hidden under the one on show.
    public static let sameColumn = 20.0
    /// Edges closer than this are the same edge.
    public static let sameEdge = 4.0

    /// The pane to the left (or right) of the one the pointer is in: the nearest by its middle,
    /// then the one level with the pointer, skipping any in the same place and any whose middle
    /// is inside the pane the pointer is in, where the pointer would not leave it. With the
    /// pointer in no pane, the nearest that way from the pointer, else the largest. Nil at the
    /// window's edge.
    public static func next(from pointer: CGPoint, in panes: [CGRect], left: Bool) -> CGRect? {
        let panes = merged(panes)
        let current = panes.filter { $0.contains(pointer) }.min { area($0) < area($1) }
        let from = current?.midX ?? pointer.x
        let ahead = panes.filter {
            (left ? from - $0.midX : $0.midX - from) > sameColumn && !(current?.contains(spot(in: $0)) ?? false)
        }
        if let nearest = ahead.min(by: { distance($0, from, pointer) < distance($1, from, pointer) }) {
            return nearest
        }
        return current == nil ? panes.max { area($0) < area($1) } : nil
    }

    /// Copies of one pane taken as one. A browser tab hidden under the one on show keeps the
    /// size the side pane had when it was last shown, so after the pane is made narrower the
    /// window reports a wider copy under it, reaching under the chat. Panes with the same top,
    /// bottom and left or right edge that overlap are copies; together they are the part they
    /// all cover, which lies inside the copy on show, whichever that is.
    public static func merged(_ panes: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        for pane in panes {
            if let index = kept.firstIndex(where: { copies($0, pane) }) {
                kept[index] = kept[index].intersection(pane)
            } else {
                kept.append(pane)
            }
        }
        return kept
    }

    /// The chat: the pane right above the message box, across its middle.
    public static func chat(in panes: [CGRect], above box: CGRect) -> CGRect? {
        merged(panes)
            .filter { $0.minX <= box.midX && box.midX <= $0.maxX && $0.midY < box.minY }
            .max { $0.maxY < $1.maxY }
    }

    /// Where the pointer goes in a pane: its middle.
    public static func spot(in pane: CGRect) -> CGPoint {
        CGPoint(x: pane.midX, y: pane.midY)
    }

    private static func copies(_ one: CGRect, _ other: CGRect) -> Bool {
        let near = { (a: Double, b: Double) in abs(a - b) <= sameEdge }
        return near(one.minY, other.minY) && near(one.maxY, other.maxY)
            && (near(one.minX, other.minX) || near(one.maxX, other.maxX))
            && one.intersection(other).width > 0
    }

    private static func area(_ pane: CGRect) -> Double {
        pane.width * pane.height
    }

    private static func distance(_ pane: CGRect, _ x: Double, _ pointer: CGPoint) -> (Double, Double) {
        let level = pane.minY <= pointer.y && pointer.y <= pane.maxY
        return (abs(pane.midX - x), level ? 0 : abs(pane.midY - pointer.y))
    }
}
