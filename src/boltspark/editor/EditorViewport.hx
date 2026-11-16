package boltspark.editor;

import boltspark.ui.layout.LayoutRect;

/**
 * Owns bounded viewport composition and the one coordinate conversion used by
 * rendering, picking, and gizmo pointers. Keeping this outside Main prevents
 * panel-resize and backbuffer scaling rules from drifting apart.
 *
 * Render sequence (all editor-only passes stay outside the world scene):
 *   1. the world/scene renderer (gameplay objects),
 *   2. the independent editor grid scene (dedicated h3d.scene.Scene pass),
 *   3. the axis gizmo overlay (drawn within the 2D scene above everything).
 * The grid draws before the world scene — with no depth write — so scene
 * geometry always paints over it, matching the historical layering without
 * the grid ever being a node in the scene graph.
 */
class EditorViewport {
    /** Shared horizontal FOV, adjustable from the viewport camera menu. The
        camera controller derives pan scale from it live. */
    public static var VIEW_FOV_DEG:Float = 90.0;

    final window:hxd.Window;
    final scene3d:h3d.scene.Scene;
    final scene2d:h2d.Scene;
    final viewportRect:Void->LayoutRect;
    var gridRenderer:Null<EditorGridRenderer>;
    var gizmoRenderer:Null<EditorAxisGizmoRenderer>;

    public function new(window:hxd.Window, scene3d:h3d.scene.Scene,
            scene2d:h2d.Scene, viewportRect:Void->LayoutRect,
            ?grid:EditorGridRenderer, ?gizmo:EditorAxisGizmoRenderer) {
        this.window = window;
        this.scene3d = scene3d;
        this.scene2d = scene2d;
        this.viewportRect = viewportRect;
        gridRenderer = grid;
        gizmoRenderer = gizmo;
    }

    public function render(engine:h3d.Engine, backgroundColor:Int):Void {
        var viewport = viewportRect();
        var scaleX = engine.width / Math.max(1, window.width);
        var scaleY = engine.height / Math.max(1, window.height);
        var x = Std.int(Math.round(viewport.x * scaleX));
        var y = Std.int(Math.round(viewport.y * scaleY));
        var width = Std.int(Math.max(0, Math.round(viewport.width * scaleX)));
        var height = Std.int(Math.max(0, Math.round(viewport.height * scaleY)));
        if (width > 0 && height > 0) {
            var centerX = x + width * 0.5;
            var centerY = y + height * 0.5;
            scene3d.camera.setFovX(VIEW_FOV_DEG, engine.width / engine.height);
            scene3d.camera.viewX = centerX * 2 / engine.width - 1;
            scene3d.camera.viewY = 1 - centerY * 2 / engine.height;
            engine.setRenderZone(x, y, width, height);
            engine.clear(0xFF000000 | backgroundColor, 1, 0);
            // Dedicated editor grid pass, independent of the world scene.
            if (gridRenderer != null && gridRenderer.visible) {
                gridRenderer.syncCamera(scene3d.camera);
                gridRenderer.render(engine);
            }
            scene3d.render(engine);
            engine.setRenderZone();
        }
        scene2d.render(engine);
    }

    public function ray(viewX:Float, viewY:Float):h3d.col.Ray {
        var point = enginePoint(viewX, viewY);
        var engine = h3d.Engine.getCurrent();
        return scene3d.camera.rayFromScreen(
            point.x, point.y, engine.width, engine.height);
    }

    public function pointer(viewX:Float, viewY:Float):h3d.Vector {
        return enginePoint(viewX, viewY);
    }

    public function windowPoint(viewX:Float, viewY:Float):h3d.Vector {
        var viewport = viewportRect();
        return new h3d.Vector(viewport.x + viewX, viewport.y + viewY, 0);
    }

    function enginePoint(viewX:Float, viewY:Float):h3d.Vector {
        var viewport = viewportRect();
        var engine = h3d.Engine.getCurrent();
        var scaleX = engine.width / Math.max(1, window.width);
        var scaleY = engine.height / Math.max(1, window.height);
        return new h3d.Vector((viewport.x + viewX) * scaleX,
            (viewport.y + viewY) * scaleY, 0);
    }
}
