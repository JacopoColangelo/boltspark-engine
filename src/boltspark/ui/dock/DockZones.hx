package boltspark.ui.dock;

import boltspark.ui.dock.DockEnums.DockSide;
import boltspark.ui.layout.LayoutRect;

/**
 * Pure hit-testing for drop targets. Kept separate from rendering so drag
 * behavior can be unit tested without a window.
 */
class DockZones {
    /** Fraction of a group's size treated as a directional docking edge. */
    public static inline var EDGE_FRACTION:Float = 0.28;
    /** Edge bands never grow beyond this, so huge panels don't claim drops. */
    public static inline var MAX_EDGE:Float = 96;
    /** Distance outside the editor body that creates a floating window. */
    public static inline var FLOAT_MARGIN:Float = 12;

    /**
     * Resolve a pointer position inside a tab group into a docking direction.
     * The tab bar always means "join/reorder" so clicking a tab can never
     * accidentally split the group.
     */
    public static function sideFor(tab:TabNode, px:Float, py:Float):DockSide {
        var r = tab.rect;
        if (r.width <= 0 || r.height <= 0) return DockSide.Center;
        if (py <= r.y + tab.barHeight) return DockSide.Center;

        var edgeX = Math.min(r.width * EDGE_FRACTION, MAX_EDGE);
        var edgeY = Math.min(Math.max(28, r.height * EDGE_FRACTION), MAX_EDGE);
        var dl = px - r.x;
        var dr = r.x + r.width - px;
        var dt = py - r.y;
        var db = r.y + r.height - py;

        var best = Math.min(Math.min(dl, dr), Math.min(dt, db));
        if (best > Math.max(edgeX, edgeY)) return DockSide.Center;
        if (best == dl && dl <= edgeX) return DockSide.Left;
        if (best == dr && dr <= edgeX) return DockSide.Right;
        if (best == dt && dt <= edgeY) return DockSide.Top;
        if (best == db && db <= edgeY) return DockSide.Bottom;
        return DockSide.Center;
    }

    /** Force a directional side when a fixed group is dropped on centrally. */
    public static function directionalFallback(tab:TabNode, px:Float,
            py:Float):DockSide {
        var r = tab.rect;
        var nx = r.width <= 0 ? 0.5 : (px - r.x) / r.width;
        var ny = r.height <= 0 ? 0.5 : (py - r.y) / r.height;
        if (ny < 0.35) return DockSide.Top;
        if (ny > 0.65) return DockSide.Bottom;
        return nx < 0.5 ? DockSide.Left : DockSide.Right;
    }

    /** True when the pointer has left the editor body far enough to float. */
    public static function isFloatingPoint(body:LayoutRect, px:Float, py:Float):Bool {
        return px < body.x - FLOAT_MARGIN || py < body.y - FLOAT_MARGIN
            || px > body.x + body.width + FLOAT_MARGIN
            || py > body.y + body.height + FLOAT_MARGIN;
    }

    /** Clamp a floating rectangle into the editable window area. */
    public static function clampFloating(body:LayoutRect, x:Float, y:Float,
            width:Float, height:Float):LayoutRect {
        var w = Math.min(Math.max(160, width), Math.max(160, body.width));
        var h = Math.min(Math.max(100, height), Math.max(100, body.height));
        var px = DockNode.clamp(x, body.x, Math.max(body.x, body.x + body.width - w));
        var py = DockNode.clamp(y, body.y, Math.max(body.y, body.y + body.height - h));
        return new LayoutRect(px, py, w, h);
    }
}
