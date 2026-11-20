package boltspark.ui;

import boltspark.engine.Material;
import boltspark.engine.PrimitiveMeshes;
import boltspark.ui.UiIcons;

/**
 * Draws the pre-baked asset thumbnails shipped in `res/thumbnails`.
 *
 * The PNGs are real in-engine renders captured ahead of time, so the editor
 * never spins up a render target or draws 3D geometry at runtime. The 512px
 * sources are loaded directly so no mip filtering softens them.
 */
class PrimitiveThumbnails {
    static var cache:Map<String, h2d.Tile> = new Map();

    public static function draw(g:h2d.Graphics, assetId:String,
            x:Float, y:Float, width:Float, height:Float, accent:Int):Void {
        if (width <= 0 || height <= 0) return;
        var tile = tileFor(assetId);
        if (tile != null) {
            g.beginTileFill(x, y, width / tile.width, height / tile.height, tile);
            g.drawRect(x, y, width, height);
            g.endFill();
        } else {
            // Unknown/custom assets get a neutral document glyph.
            var size = Math.min(width, height);
            UiIcons.draw(g, Document, x + (width - size) * 0.5,
                y + (height - size) * 0.5, size, accent);
        }
    }

    static function tileFor(assetId:String):Null<h2d.Tile> {
        if (assetId == null) return null;
        var source:hxd.res.Image = switch (assetId) {
            case PrimitiveMeshes.CUBE_ID: hxd.Res.thumbnails.cube;
            case PrimitiveMeshes.SPHERE_ID: hxd.Res.thumbnails.sphere;
            case PrimitiveMeshes.CYLINDER_ID: hxd.Res.thumbnails.cylinder;
            case PrimitiveMeshes.CAPSULE_ID: hxd.Res.thumbnails.capsule;
            case PrimitiveMeshes.PLANE_ID: hxd.Res.thumbnails.plane;
            default: Material.find(assetId) != null
                ? hxd.Res.thumbnails.material : null;
        };
        if (source == null) return null;
        var found = cache.get(assetId);
        if (found != null) return found;
        var tile = source.toTile();
        cache.set(assetId, tile);
        return tile;
    }

}
