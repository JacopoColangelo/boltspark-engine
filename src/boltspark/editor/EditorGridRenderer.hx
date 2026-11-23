package boltspark.editor;

import boltspark.editor.shaders.OverlayDepthOcclusion;
import boltspark.ui.Theme;

/**
 * Independent editor floor grid.
 *
 * The grid is a non-serialized helper object inside the world scene, drawn in
 * the deferred renderer's `overlay` pass after tonemapping. It is never part
 * of the editor session, hierarchy, picking, or scene documents. A small
 * shader discards grid fragments hidden by the PBR depth buffer, preserving
 * the historical "objects sit in front of the grid" look (and the dedicated
 * render pass is gone, so the deferred final blit cannot overwrite it).
 *
 * Visibility is controlled through `visible` (G / Game View).
 */
class EditorGridRenderer {
    static inline var EXTENT:Int = 20;
    static inline var MAJOR_STEP:Int = 5;

    public var visible(default, set):Bool = true;

    /** Grid graphics node; deliberately not tracked by the editor session. */
    public final grid:h3d.scene.Graphics;

    public function new(parent:h3d.scene.Object) {
        grid = new h3d.scene.Graphics(parent);
        grid.name = "EditorGrid";
        grid.material.mainPass.setPassName("overlay");
        grid.material.mainPass.depthWrite = false;
        // The LDR overlay target has no depth buffer: visibility is resolved
        // against the PBR depth texture inside OverlayDepthOcclusion.
        grid.material.mainPass.depthTest = h3d.mat.Data.Compare.Always;
        grid.material.mainPass.layer = 5;
        grid.material.mainPass.addShader(new OverlayDepthOcclusion());
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

    function set_visible(value:Bool):Bool {
        grid.visible = value;
        return visible = value;
    }
}
