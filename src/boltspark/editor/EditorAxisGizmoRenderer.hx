package boltspark.editor;

import boltspark.ui.Theme;
import boltspark.ui.UiText;
import boltspark.ui.layout.LayoutRect;

/**
 * Editor viewport orientation gizmo — the Unreal-style XYZ indicator.
 *
 * This is a dedicated editor overlay, not a node in the 3D world: it owns
 * its own h2d object graph placed directly in the UI overlay scene, derives
 * its orientation from the editor camera's view basis every frame, anchors
 * to the viewport's bottom-right corner, and creates no interactives, so it
 * never intercepts scene mouse picking. It is unaffected by scene object
 * transforms, invisible to scene inspection, and stays compact at every
 * viewport size.
 *
 * The three world axes are projected into screen space and painted in depth
 * order, so positive/negative directions and occlusion stay correct at any
 * camera orientation without a second 3D render pass. Letters mark the
 * positive tips; negative directions render as dimmer, shorter lines.
 */
class EditorAxisGizmoRenderer {
    public var visible(default, set):Bool = true;

    static inline var AXIS_PIXELS:Float = 26.0;
    static inline var NEGATIVE_RATIO:Float = 0.62;
    static inline var LABEL_GAP:Float = 9.0;
    static inline var CORNER_MARGIN:Float = 12.0;
    static inline var POSITIVE_WIDTH:Float = 2.0;
    static inline var NEGATIVE_WIDTH:Float = 1.2;
    static inline var NEGATIVE_ALPHA:Float = 0.38;
    static inline var MIN_VIEWPORT_EDGE:Float = 120.0;

    final camera:h3d.Camera;
    final viewportRect:Void->LayoutRect;
    final overlay:h2d.Object;
    final lines:h2d.Graphics;
    final labels:Array<UiText> = [];

    // Camera basis and its last-drawn copy; identical bases skip redraws so
    // a still camera costs nothing.
    final forward = new h3d.Vector();
    final right = new h3d.Vector();
    final screenUp = new h3d.Vector();
    final lastForward = new h3d.Vector();
    final lastRight = new h3d.Vector();
    final lastUp = new h3d.Vector();
    var basisCaptured:Bool = false;
    var lastCenterX:Float = -1;
    var lastCenterY:Float = -1;

    public function new(camera:h3d.Camera, parent:h2d.Object, font:h2d.Font,
            viewportRect:Void->LayoutRect) {
        this.camera = camera;
        this.viewportRect = viewportRect;
        overlay = new h2d.Object(parent);
        overlay.name = "EditorAxisGizmo";
        lines = new h2d.Graphics(overlay);
        if (font != null) {
            for (index in 0...3) {
                var label = new UiText(font, overlay);
                label.text = index == 0 ? "X" : index == 1 ? "Y" : "Z";
                label.textColor = axisColor(index);
                label.lineBreak = false;
                labels.push(label);
            }
        }
    }

    /**
     * Refresh overlay geometry from the camera. Call once per frame after
     * camera navigation and layout updates; a still camera and unchanged
     * corner skip all redrawing.
     */
    public function update():Void {
        if (!visible) return;
        var rect = viewportRect();
        if (rect == null || rect.width < MIN_VIEWPORT_EDGE
                || rect.height < MIN_VIEWPORT_EDGE) {
            overlay.visible = false;
            return;
        }
        overlay.visible = true;
        readBasis();
        var centerX = rect.x + rect.width - CORNER_MARGIN - AXIS_PIXELS - LABEL_GAP;
        var centerY = rect.y + rect.height - CORNER_MARGIN - AXIS_PIXELS - LABEL_GAP;
        if (basisCaptured && sameBasis()
                && centerX == lastCenterX && centerY == lastCenterY) {
            return;
        }
        basisCaptured = true;
        lastCenterX = centerX;
        lastCenterY = centerY;
        lastForward.load(forward);
        lastRight.load(right);
        lastUp.load(screenUp);
        redraw(centerX, centerY);
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function readBasis():Void {
        var fx = camera.target.x - camera.pos.x;
        var fy = camera.target.y - camera.pos.y;
        var fz = camera.target.z - camera.pos.z;
        var length = Math.sqrt(fx * fx + fy * fy + fz * fz);
        if (length > 0.000001) {
            forward.set(fx / length, fy / length, fz / length);
        } else {
            forward.set(0, 0, -1);
        }
        // Screen right is world up crossed with the view forward.
        var rx = forward.z;
        var rz = -forward.x;
        var rightLength = Math.sqrt(rx * rx + rz * rz);
        if (rightLength < 0.000001) {
            right.set(1, 0, 0);
        } else {
            right.set(rx / rightLength, 0, rz / rightLength);
        }
        // Screen up is forward crossed with right.
        screenUp.set(
            forward.y * right.z,
            forward.z * right.x - forward.x * right.z,
            -forward.y * right.x);
        var upLength = Math.sqrt(screenUp.x * screenUp.x
            + screenUp.y * screenUp.y + screenUp.z * screenUp.z);
        if (upLength > 0.000001) {
            screenUp.x /= upLength;
            screenUp.y /= upLength;
            screenUp.z /= upLength;
        }
    }

    function sameBasis():Bool {
        return basisCaptured
            && forward.dot(lastForward) > 0.999999
            && right.dot(lastRight) > 0.999999
            && screenUp.dot(lastUp) > 0.999999;
    }

    /** Screen-space direction of a world unit axis: (x, y) with y downward. */
    function projectAxis(axisIndex:Int, sign:Float):h3d.Vector {
        return switch (axisIndex) {
            case 0:
                new h3d.Vector((right.x * sign) * AXIS_PIXELS,
                    -(screenUp.x * sign) * AXIS_PIXELS, axisDepth(0, sign));
            case 1:
                new h3d.Vector((right.y * sign) * AXIS_PIXELS,
                    -(screenUp.y * sign) * AXIS_PIXELS, axisDepth(1, sign));
            default:
                new h3d.Vector((right.z * sign) * AXIS_PIXELS,
                    -(screenUp.z * sign) * AXIS_PIXELS, axisDepth(2, sign));
        };
    }

    /** View-axis depth of an axis direction: smaller means farther away. */
    function axisDepth(axisIndex:Int, sign:Float):Float {
        return switch (axisIndex) {
            case 0: forward.x * sign;
            case 1: forward.y * sign;
            default: forward.z * sign;
        };
    }

    function axisColor(axisIndex:Int):Int {
        return switch (axisIndex) {
            case 0: Theme.GIZMO_AXIS_X;
            case 1: Theme.GIZMO_AXIS_Y;
            default: Theme.GIZMO_AXIS_Z;
        };
    }

    function redraw(centerX:Float, centerY:Float):Void {
        lines.clear();
        // Painter order: draw the axes pointing away from the camera first
        // so the ones facing the viewer stay on top, Unreal-style.
        var order:Array<Int> = [];
        var projected:Array<h3d.Vector> = [];
        for (axis in 0...3) {
            for (sign in [-1.0, 1.0]) {
                order.push(order.length);
                projected.push(projectAxis(axis, sign));
            }
        }
        // Stable insertion sort by depth (6 entries; allocation-free sort).
        for (i in 1...order.length) {
            var index = order[i];
            var depth = projected[index].z;
            var j = i - 1;
            while (j >= 0 && projected[order[j]].z > depth) {
                order[j + 1] = order[j];
                j--;
            }
            order[j + 1] = index;
        }
        for (slot in order) {
            var axis = slot >> 1;
            var positive = (slot & 1) == 1;
            var direction = projected[slot];
            var reach = positive ? AXIS_PIXELS : AXIS_PIXELS * NEGATIVE_RATIO;
            if (positive) {
                lines.lineStyle(POSITIVE_WIDTH, axisColor(axis), 1);
            } else {
                lines.lineStyle(NEGATIVE_WIDTH, axisColor(axis), NEGATIVE_ALPHA);
            }
            lines.moveTo(centerX, centerY);
            lines.lineTo(centerX + direction.x * reach / AXIS_PIXELS,
                centerY + direction.y * reach / AXIS_PIXELS);
        }
        // Positive-axis letters just beyond each tip, always on top.
        for (axis in 0...labels.length) {
            var label = labels[axis];
            var direction = projected[axis * 2 + 1];
            label.x = centerX + direction.x
                + direction.x / AXIS_PIXELS * LABEL_GAP
                - label.textWidth * 0.5;
            label.y = centerY + direction.y
                + direction.y / AXIS_PIXELS * LABEL_GAP
                - label.textHeight * 0.5;
        }
    }

    function set_visible(value:Bool):Bool {
        overlay.visible = value;
        return visible = value;
    }
}
