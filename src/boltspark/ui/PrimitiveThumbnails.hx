package boltspark.ui;

import boltspark.engine.Material;
import boltspark.engine.PrimitiveMeshes;
import boltspark.thumbnails.ThumbnailBaker;
import boltspark.thumbnails.ThumbnailLoader;
import boltspark.ui.UiIcons;

/**
 * Draws the engine-content thumbnails in the Asset Browser and asset pickers.
 *
 * The only source is the offline-baked mipmapped bundle produced by
 * `ThumbnailBaker` (`res/thumbnails/bundles/*.bundle`). Each bundle carries a
 * complete pre-filtered pyramid, so the continuous thumbnail-size slider can
 * rescale it with trilinear filtering and zero runtime 3D rendering.
 */
class PrimitiveThumbnails {
    static var cache:Map<String, h2d.Tile> = new Map();

    public static function draw(g:h2d.Graphics, assetId:String,
            x:Float, y:Float, width:Float, height:Float, accent:Int):Void {
        if (width <= 0 || height <= 0) return;
        var tile = tileFor(assetId);
        if (tile != null) {
            // h2d.RenderContext rewrites texture.filter from the drawing
            // object's `smooth` flag on every draw. The editor sets
            // defaultSmooth = false for pixel-exact icons, which would give
            // the mipmapped thumbnail MIN_MAG_POINT_MIP_LINEAR (point sampling
            // inside a mip) and make it blocky when the slider shrinks it.
            // These Graphics objects are dedicated to the thumbnail, so opting
            // just them into smooth sampling yields true trilinear filtering.
            g.smooth = true;
            g.beginTileFill(x, y, width / tile.width, height / tile.height, tile);
            g.drawRect(x, y, width, height);
            g.endFill();
        } else {
            // Unknown/custom assets get a neutral document glyph.
            g.smooth = false;
            var size = Math.min(width, height);
            UiIcons.draw(g, Document, x + (width - size) * 0.5,
                y + (height - size) * 0.5, size, accent);
        }
    }

    /** Drop cached tiles, e.g. alongside `ThumbnailLoader.clear()` on teardown. */
    public static function clearCache():Void {
        cache.clear();
    }

    static function tileFor(assetId:String):Null<h2d.Tile> {
        if (assetId == null) return null;
        var found = cache.get(assetId);
        if (found != null) return found;

        var resourceName:String = switch (assetId) {
            case PrimitiveMeshes.CUBE_ID: "cube";
            case PrimitiveMeshes.SPHERE_ID: "sphere";
            case PrimitiveMeshes.CYLINDER_ID: "cylinder";
            case PrimitiveMeshes.CAPSULE_ID: "capsule";
            case PrimitiveMeshes.PLANE_ID: "plane";
            default: {
                var material = Material.find(assetId);
                material == null ? null : ThumbnailBaker.materialBundleName(material.id);
            }
        };
        if (resourceName == null) return null;

        var tile = ThumbnailLoader.get(assetId, resourceName);
        if (tile != null) cache.set(assetId, tile);
        return tile;
    }
}
