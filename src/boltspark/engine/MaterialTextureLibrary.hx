package boltspark.engine;

import boltspark.engine.MaterialTexture;

/**
 * Catalog of imported textures available as material albedo maps, plus the
 * id -> absolute path resolver. Pure data so it compiles in headless tests;
 * GPU loading lives in `MaterialTextureBindings` and is only used by the
 * renderer. Main refreshes this catalog after every asset change.
 */
class MaterialTextureLibrary {
    static var textures:Array<MaterialTexture> = [];

    /** Project-relative texture id -> absolute file path. Set by Main. */
    public static var resolvePath:Null<String->String> = null;

    public static function setTextures(list:Array<MaterialTexture>):Void {
        textures = list == null ? [] : list.copy();
    }

    public static function all():Array<MaterialTexture> return textures.copy();

    public static function find(id:String):Null<MaterialTexture> {
        if (id == null || id.length == 0) return null;
        for (texture in textures) {
            if (texture.id == id) return texture;
        }
        return null;
    }

    public static function clear():Void {
        textures = [];
        resolvePath = null;
    }
}
