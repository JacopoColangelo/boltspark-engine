package boltspark.ui;

enum abstract UiIconKind(Int) from Int to Int {
    var None = 0;
    var Add = 1;
    var Trash = 2;
    var Cube = 3;
    var Search = 4;
    var Play = 5;
    var Pause = 6;
    var Stop = 7;
    var Move = 8;
    var Rotate = 9;
    var Scale = 10;
    var ChevronDown = 11;
    var ChevronRight = 12;
    var Console = 13;
    var Sliders = 14;
    var Hierarchy = 15;
    var Close = 16;
    var Grid = 17;
    var More = 18;
    var ChevronUp = 19;
    var StatusDot = 20;
    var Link = 21;
    var Unlink = 22;
    var Reset = 23;
    var Folder = 24;
    var Scene = 25;
    var Sort = 26;
    var Filter = 27;
    var Settings = 28;
    var List = 29;
    var Table = 30;
    var Document = 31;
    var Box = 32;
    var Star = 33;
    var ArrowLeft = 34;
    var ArrowRight = 35;
    var ArrowUp = 36;
    var Eye = 37;
    var EyeOff = 38;
    var Camera = 39;
    var Check = 40;
    var Minus = 41;
    var Eraser = 42;
    // Docking tab icons.
    var DockPanel = 43;
    var DockSide = 44;
    var DockBottom = 45;
    var ArrowDown = 46;
}

/**
 * Exact-size Tabler editor icons from the embedded, pre-rasterized atlas.
 *
 * The atlas contains a dedicated raster for every supported integer size, so
 * small controls never downscale a large texture at runtime. Pixels are white
 * with alpha coverage and are tinted here to follow the active UI state.
 *
 * Source mapping and MIT license: `third_party/tabler-icons/README.md`.
 */
class UiIcons {
    static inline var CELL_SIZE:Int = 16;
    static inline var ICON_COLUMNS:Int = 47;
    static inline var MIN_SIZE:Int = 6;
    static inline var MAX_SIZE:Int = 16;

    static var atlas:h2d.Tile;
    static var sceneThumb:h2d.Tile;
    static var folderThumb:h2d.Tile;

    /** Large tinted Tabler `outline/photo` glyph for asset-browser scene
     *  thumbnails; the exact-size atlas tops out at 16px. */
    public static function drawSceneThumb(target:h2d.Graphics, x:Float, y:Float,
            size:Float, color:Int, alpha:Float = 1):Void {
        target.removeChildren();
        if (sceneThumb == null) sceneThumb = hxd.Res.icons.scene_thumb.toTile();
        var bitmap = new h2d.Bitmap(sceneThumb, target);
        bitmap.x = Math.round(x);
        bitmap.y = Math.round(y);
        bitmap.width = size;
        bitmap.height = size;
        bitmap.smooth = true;
        bitmap.color.setColor(color);
        bitmap.color.a = Math.max(0, Math.min(1, alpha));
    }

    /** Large tinted Tabler `outline/folder` glyph for asset-browser folder
     *  tiles; the exact-size atlas tops out at 16px and looks blurry scaled up. */
    public static function drawFolderThumb(target:h2d.Graphics, x:Float, y:Float,
            size:Float, color:Int, alpha:Float = 1):Void {
        target.removeChildren();
        if (folderThumb == null) folderThumb = hxd.Res.icons.folder_thumb.toTile();
        var bitmap = new h2d.Bitmap(folderThumb, target);
        bitmap.x = Math.round(x);
        bitmap.y = Math.round(y);
        bitmap.width = size;
        bitmap.height = size;
        bitmap.smooth = true;
        bitmap.color.setColor(color);
        bitmap.color.a = Math.max(0, Math.min(1, alpha));
    }

    public static function draw(target:h2d.Graphics, kind:UiIconKind, x:Float, y:Float,
            size:Float, color:Int, alpha:Float = 1):Void {
        target.removeChildren();
        if (kind == None || size <= 0) return;

        var pixelSize = Math.max(1, Math.round(size));
        var atlasSize = Std.int(Math.max(MIN_SIZE, Math.min(MAX_SIZE, pixelSize)));
        var tile = getAtlas().sub(
            kind * CELL_SIZE,
            (atlasSize - MIN_SIZE) * CELL_SIZE,
            atlasSize,
            atlasSize);

        var bitmap = new h2d.Bitmap(tile, target);
        bitmap.x = Math.round(x);
        bitmap.y = Math.round(y);
        // Current BoltUI controls use 6..16 px exactly. Retain a graceful
        // fallback for future out-of-range callers without expanding the
        // embedded atlas: only those uncommon sizes use filtered scaling.
        if (pixelSize != atlasSize) {
            bitmap.width = pixelSize;
            bitmap.height = pixelSize;
            bitmap.smooth = true;
        } else {
            bitmap.smooth = false;
        }
        bitmap.color.setColor(color);
        bitmap.color.a = Math.max(0, Math.min(1, alpha));
    }

    static function getAtlas():h2d.Tile {
        if (atlas == null) {
            atlas = hxd.Res.icons.tabler_ui.toTile();
            var expectedWidth = ICON_COLUMNS * CELL_SIZE;
            var expectedHeight = (MAX_SIZE - MIN_SIZE + 1) * CELL_SIZE;
            if (atlas.width != expectedWidth || atlas.height != expectedHeight) {
                throw 'Invalid Tabler icon atlas: expected ${expectedWidth}x${expectedHeight}, '
                    + 'got ${atlas.width}x${atlas.height}';
            }
            atlas.getTexture().filter = h3d.mat.Data.Filter.Nearest;
        }
        return atlas;
    }
}
