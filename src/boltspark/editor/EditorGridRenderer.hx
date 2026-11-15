package boltspark.editor;

import boltspark.ui.Theme;

/**
 * Independent editor floor grid.
 *
 * The grid lives in its own h3d.scene.Scene that is rendered as a dedicated
 * editor pass by EditorViewport — it is never parented into the gameplay
 * scene graph, never serialized with a scene, and never visible to hierarchy
 * inspection. Its camera is synchronized from the editor camera every frame,
 * so the grid stays aligned with the world origin at any camera position.
 *
 * Depth behavior matches the previous in-scene layering: the grid draws
 * before the world scene with no depth write, so scene geometry always
 * paints over it (objects appear naturally in front of the grid), while the
 * grid itself stays anchored to y = 0 regardless of scene transforms.
 *
 * Visibility is controlled through `visible` (G / Game View). Toggling only
 * flips the render flag: scene rendering, camera navigation and the axis
 * gizmo are untouched, and the grid resources are kept alive for the next
 * toggle.
 */
class EditorGridRenderer {
    static inline var EXTENT:Int = 20;
    static inline var MAJOR_STEP:Int = 5;

    public var visible(default, set):Bool = true;

    /** Dedicated editor render scene; never part of the world hierarchy. */
    public final scene:h3d.scene.Scene;
    final grid:h3d.scene.Graphics;

    public function new() {
        scene = new h3d.scene.Scene();
        grid = new h3d.scene.Graphics(scene);
        grid.name = "EditorGrid";
        grid.material.mainPass.depthWrite = false;
        build();
    }

    function build():Void {
        // The visible editor origin is y=0. A tiny negative bias avoids line
        // z-fighting without baking the centered cube's half-height into
        // every empty GameObject's apparent pivot.
        var gridY = -0.005;
        for (i in -EXTENT...(EXTENT + 1)) {
            var major = i % MAJOR_STEP == 0;
            grid.lineStyle(major ? 1.0 : 0.75,
                major ? 0x384450 : 0x252D37, 1);
            grid.moveTo(i, gridY, -EXTENT);
            grid.lineTo(i, gridY, EXTENT);
            grid.moveTo(-EXTENT, gridY, i);
            grid.lineTo(EXTENT, gridY, i);
        }
        // Ground-plane axis highlights: X along its axis, Z along its axis.
        grid.lineStyle(1.35, Theme.AXIS_X, 1);
        grid.moveTo(-EXTENT, gridY + 0.003, 0);
        grid.lineTo(EXTENT, gridY + 0.003, 0);
        grid.lineStyle(1.35, Theme.AXIS_Z, 1);
        grid.moveTo(0, gridY + 0.003, -EXTENT);
        grid.lineTo(0, gridY + 0.003, EXTENT);
    }

    /** Copy the editor camera so the grid view matches the world exactly. */
    public function syncCamera(camera:h3d.Camera):Void {
        scene.camera.load(camera);
    }

    /** Render the dedicated editor grid pass. */
    public function render(engine:h3d.Engine):Void {
        if (!visible) return;
        scene.render(engine);
    }

    function set_visible(value:Bool):Bool {
        grid.visible = value;
        return visible = value;
    }
}
