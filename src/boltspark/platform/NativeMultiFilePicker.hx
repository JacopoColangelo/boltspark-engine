package boltspark.platform;

/**
 * Haxe binding for the project-local `bin/multifile.hdll` Windows picker.
 *
 * HashLink's `hl.UI.loadFile()` only returns one path and has no multi-select
 * flag; this native module uses the same common item dialog with
 * `FOS_ALLOWMULTISELECT` so a whole texture set can be imported in one command.
 * Strings cross the boundary as null-terminated UTF-16 (`hl.Bytes`), which is
 * exactly what `String.fromUCS2` consumes on the HashLink target.
 */
class NativeMultiFilePicker {
    #if hl
    @:hlNative("multifile", "load_images")
    static function loadImages(title:hl.Bytes, titleLength:Int,
        filterName:hl.Bytes, filterNameLength:Int,
        filterSpec:hl.Bytes, filterSpecLength:Int):hl.NativeArray<hl.Bytes> return null;
    #end

    /**
     * @return the chosen absolute paths, or null when the dialog was cancelled.
     */
    public static function pickImages(title:String, filterName:String,
            filterSpec:String):Null<Array<String>> {
        #if hl
        var raw = loadImages(@:privateAccess title.bytes, title.length,
            @:privateAccess filterName.bytes, filterName.length,
            @:privateAccess filterSpec.bytes, filterSpec.length);
        if (raw == null || raw.length == 0) return null;
        var result:Array<String> = [];
        for (index in 0...raw.length) {
            var bytes = raw[index];
            if (bytes == null) continue;
            result.push(@:privateAccess String.fromUCS2(bytes));
        }
        return result.length == 0 ? null : result;
        #else
        return null;
        #end
    }
}
