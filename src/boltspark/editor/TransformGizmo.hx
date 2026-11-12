package boltspark.editor;

import boltspark.ui.Theme;

/**
 * Move-tool axis gizmo drawn in s3d at the primary selection's position.
 *
 * The gizmo renders through the same DX12 driver as the scene (always-on-top
 * line graphics that never write depth) and contains all of the constrained
 * drag math: axis hit-testing and pointer-ray projection happen against
 * world-space axis lines, so no UI or screen state leaks in here. Main
 * converts viewport pointer coordinates to rays and applies returned
 * positions through the editor command flow; the gizmo never mutates scene
 * objects itself.
 *
 * Rotate and Scale gizmos are a later milestone; until then non-Move tools
 * hide this gizmo.
 */
class TransformGizmo {
    static inline var AXIS_LENGTH:Float = 1.05;
    static inline var HEAD_LENGTH:Float = 0.2;
    static inline var HEAD_RADIUS:Float = 0.085;
    static inline var PICK_THRESHOLD:Float = 0.16;
    static inline var LINE_WIDTH:Float = 2.2;
    static inline var LINE_WIDTH_ACTIVE:Float = 3.2;
    static inline var MOVE_TOOL:Int = 0;

    final graphics:h3d.scene.Graphics;
    /** Reusable solver result (the gizmo solves one axis at a time). */
    final closest:AxisRayClosest = new AxisRayClosest();
    var attached:h3d.scene.Object;
    var currentTool:Int = MOVE_TOOL;
    var hoverAxis:Int = -1;
    var dragAxis:Int = -1;
    /** World position of the attached object when the drag started. */
    final dragStartPos:h3d.Vector;
    /** Pointer-ray parameter captured on the axis when the drag started. */
    var dragAnchorT:Float = 0;

    public function new(parent:h3d.scene.Object) {
        graphics = new h3d.scene.Graphics(parent);
        graphics.name = "MoveGizmo";
        graphics.material.mainPass.depthWrite = false;
        graphics.material.mainPass.depthTest = h3d.mat.Data.Compare.Always;
        graphics.visible = false;
        dragStartPos = new h3d.Vector();
    }

    /** Attach the gizmo to an object (or detach with null). */
    public function attach(target:Null<h3d.scene.Object>):Void {
        attached = target;
        hoverAxis = -1;
        dragAxis = -1;
        refresh();
    }

    /** Switch the active viewport tool; only the Move tool shows a gizmo. */
    public function setTool(tool:Int):Void {
        currentTool = tool;
        hoverAxis = -1;
        dragAxis = -1;
        refresh();
    }

    /** Highlight the axis under the pointer; returns true on a change. */
    public function setHover(axis:Int):Bool {
        if (dragAxis >= 0 || axis == hoverAxis) return false;
        hoverAxis = axis;
        redraw();
        return true;
    }

    /** Keep the gizmo glued to the attached object's position; call per frame. */
    public function follow():Void {
        if (attached == null || !graphics.visible) return;
        graphics.setPosition(attached.x, attached.y, attached.z);
    }

    /**
     * Start a constrained drag of `axis` on `target` using the pointer ray
     * that triggered it. The ray's parameter on the axis is captured as the
     * anchor so the object does not jump to the pointer line on the first move.
     */
    public function beginDrag(axis:Int, target:h3d.scene.Object, ray:h3d.col.Ray):Void {
        dragAxis = axis;
        dragStartPos.set(target.x, target.y, target.z);
        solveAxisRay(dragStartPos, axisVector(axis), ray, closest);
        dragAnchorT = closest.valid ? closest.axisT : 0;
        hoverAxis = -1;
        redraw();
    }

    /**
     * Move the drag along its axis for the current pointer ray. Returns the
     * new absolute world position, or null when the ray is parallel to the
     * axis (the drag keeps the last valid position in that case).
     */
    public function dragTo(ray:h3d.col.Ray):Null<h3d.Vector> {
        if (dragAxis < 0) return null;
        solveAxisRay(dragStartPos, axisVector(dragAxis), ray, closest);
        if (!closest.valid) return null;
        var delta = closest.axisT - dragAnchorT;
        var axis = axisVector(dragAxis);
        return new h3d.Vector(
            dragStartPos.x + axis.x * delta,
            dragStartPos.y + axis.y * delta,
            dragStartPos.z + axis.z * delta);
    }

    /** End the active drag and return to hover highlighting. */
    public function endDrag():Void {
        dragAxis = -1;
        redraw();
    }

    /**
     * Pick the gizmo axis nearest the pointer ray, or -1. A candidate must
     * pass within PICK_THRESHOLD world units of the axis segment (including
     * the arrowhead) and in front of the camera.
     */
    public function pickAxis(ray:h3d.col.Ray):Int {
        if (attached == null || currentTool != MOVE_TOOL) return -1;
        var origin = new h3d.Vector(attached.x, attached.y, attached.z);
        var bestDistance = PICK_THRESHOLD;
        var bestAxis = -1;
        for (axis in 0...3) {
            var direction = axisVector(axis);
            solveAxisRay(origin, direction, ray, closest);
            if (!closest.valid || closest.axisT < -0.05
                    || closest.axisT > AXIS_LENGTH + 0.05) continue;
            if (closest.distance < bestDistance) {
                bestDistance = closest.distance;
                bestAxis = axis;
            }
        }
        return bestAxis;
    }

    static function axisVector(axis:Int):h3d.Vector {
        return switch (axis) {
            case 0: new h3d.Vector(1, 0, 0);
            case 1: new h3d.Vector(0, 1, 0);
            default: new h3d.Vector(0, 0, 1);
        };
    }

    static function axisColor(axis:Int, active:Bool):Int {
        return switch (axis) {
            case 0: active ? Theme.AXIS_X_HOVER : Theme.AXIS_X;
            case 1: active ? Theme.AXIS_Y_HOVER : Theme.AXIS_Y;
            default: active ? Theme.AXIS_Z_HOVER : Theme.AXIS_Z;
        };
    }

    /**
     * Solve the closest points between the pointer ray and the axis line
     * (origin + t * axis, `axis` unit) with the standard two-line solution:
     * with r = rayOrigin - origin, a = D·D, b = D·A, c = A·A, d = D·r,
     * e = A·r, the parameters are s = (b·e - c·d)/denom on the ray and
     * t = (a·e - b·d)/denom on the axis. `out.valid` is false when the lines
     * are parallel (denom ~ 0) and no unique constraint exists.
     */
    static function solveAxisRay(origin:h3d.Vector, axis:h3d.Vector,
            ray:h3d.col.Ray, out:AxisRayClosest):Void {
        var wx = ray.px - origin.x;
        var wy = ray.py - origin.y;
        var wz = ray.pz - origin.z;
        var a = ray.lx * ray.lx + ray.ly * ray.ly + ray.lz * ray.lz;
        var b = ray.lx * axis.x + ray.ly * axis.y + ray.lz * axis.z;
        var c = axis.x * axis.x + axis.y * axis.y + axis.z * axis.z;
        var d = ray.lx * wx + ray.ly * wy + ray.lz * wz;
        var e = axis.x * wx + axis.y * wy + axis.z * wz;
        var denom = a * c - b * b;
        if (Math.abs(denom) < 1e-9) {
            out.valid = false;
            return;
        }
        out.valid = true;
        var rayS = (b * e - c * d) / denom;
        out.axisT = (a * e - b * d) / denom;
        var dx = ray.px + ray.lx * rayS - (origin.x + axis.x * out.axisT);
        var dy = ray.py + ray.ly * rayS - (origin.y + axis.y * out.axisT);
        var dz = ray.pz + ray.lz * rayS - (origin.z + axis.z * out.axisT);
        out.distance = Math.sqrt(dx * dx + dy * dy + dz * dz);
    }

    function refresh():Void {
        graphics.visible = attached != null && currentTool == MOVE_TOOL;
        if (graphics.visible) redraw();
    }

    function redraw():Void {
        graphics.clear();
        for (axis in 0...3) {
            var active = axis == hoverAxis || axis == dragAxis;
            graphics.lineStyle(active ? LINE_WIDTH_ACTIVE : LINE_WIDTH,
                axisColor(axis, active), 1);
            drawAxisArrow(axis);
        }
    }

    /** Shaft line plus a four-segment arrowhead cone for one axis. */
    function drawAxisArrow(axis:Int):Void {
        var direction = axisVector(axis);
        var headStart = AXIS_LENGTH - HEAD_LENGTH;
        graphics.moveTo(0, 0, 0);
        graphics.lineTo(direction.x * headStart, direction.y * headStart,
            direction.z * headStart);

        // Two unit vectors perpendicular to the axis span the arrowhead base.
        var u:Null<h3d.Vector> = null;
        var v:Null<h3d.Vector> = null;
        switch (axis) {
            case 0:
                u = new h3d.Vector(0, 1, 0);
                v = new h3d.Vector(0, 0, 1);
            case 1:
                u = new h3d.Vector(1, 0, 0);
                v = new h3d.Vector(0, 0, 1);
            default:
                u = new h3d.Vector(1, 0, 0);
                v = new h3d.Vector(0, 1, 0);
        }
        var tipX = direction.x * AXIS_LENGTH;
        var tipY = direction.y * AXIS_LENGTH;
        var tipZ = direction.z * AXIS_LENGTH;
        for (edge in [[1, 1], [1, -1], [-1, -1], [-1, 1]]) {
            graphics.moveTo(tipX, tipY, tipZ);
            graphics.lineTo(
                direction.x * headStart + u.x * HEAD_RADIUS * edge[0] + v.x * HEAD_RADIUS * edge[1],
                direction.y * headStart + u.y * HEAD_RADIUS * edge[0] + v.y * HEAD_RADIUS * edge[1],
                direction.z * headStart + u.z * HEAD_RADIUS * edge[0] + v.z * HEAD_RADIUS * edge[1]);
        }
    }
}

/** Reusable result holder for the axis/pointer-ray closest-point solver. */
private class AxisRayClosest {
    public var valid:Bool = false;
    /** Parameter along the axis line. */
    public var axisT:Float = 0;
    /** World distance between the two closest points. */
    public var distance:Float = 0;

    public function new() {}
}
