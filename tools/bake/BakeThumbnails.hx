import boltspark.thumbnails.ThumbnailBaker;

/**
 * Build-time host for `ThumbnailBaker`.
 *
 * Baking needs a live GPU context, so this tiny hxd.App exists only to give the
 * baker an h3d.Engine. It renders nothing on screen: on `init()` it bakes all
 * engine primitive thumbnails into `src/res/thumbnails/*.bundle`, prints a
 * short report and exits. The main editor binary contains no copy of this
 * command, so there is no runtime 3D thumbnail work in the shipped game.
 *
 * Run with `tools\bake-thumbnails.ps1` or compile `tools\bake\bake-thumbnails.hxml`.
 */
class BakeThumbnails extends hxd.App {
    static function main():Void {
        new BakeThumbnails();
    }

    override function init():Void {
        var output = Sys.getEnv("BOLTSPARK_THUMBNAIL_DIR");
        if (output == null || StringTools.trim(output).length == 0) {
            output = haxe.io.Path.join([Sys.getCwd(), "src", "res", "thumbnails"]);
        }
        Sys.println('[bake] ${ThumbnailBaker.RESOLUTION}x${ThumbnailBaker.RESOLUTION} '
            + 'offline thumbnail bake -> ' + output);
        try {
            for (line in ThumbnailBaker.bakeEngineContent(output)) {
                Sys.println("[bake] " + line);
            }
            Sys.println("[bake] complete");
            Sys.exit(0);
        } catch (error:Dynamic) {
            Sys.println("[bake] FAILED: " + Std.string(error));
            Sys.exit(1);
        }
    }

    override function render(engine:h3d.Engine):Void {
        // The bake command never presents a frame; it only borrows the engine.
    }
}
