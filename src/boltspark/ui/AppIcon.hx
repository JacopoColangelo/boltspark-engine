package boltspark.ui;

private typedef IconDirectoryEntry = {
    var width:Int;
    var height:Int;
    var size:Int;
    var offset:Int;
}

/**
 * Loads the embedded multi-resolution Boltspark icon for native HWNDs and H2D.
 *
 * Keeping the ICO as the single source asset ensures the executable, taskbar,
 * native windows, and editor chrome all use the same artwork.
 */
class AppIcon {
    static inline var TITLE_BAR_ICON_SIZE:Int = 24;
    static inline var NATIVE_WINDOW_ICON_SIZE:Int = 64;

    static var sourceBytes:haxe.io.Bytes;
    static var titleBarPixels:hxd.Pixels;
    static var titleBarTile:h2d.Tile;

    /** Apply the embedded artwork to the live native window. */
    public static function applyToWindow(window:hxd.Window):Void {
        #if hldx
        var pixels = decodeClosestFrame(NATIVE_WINDOW_ICON_SIZE);
        pixels.convert(hxd.PixelFormat.BGRA);
        @:privateAccess window.window.setIcon(pixels.width, pixels.height, pixels.bytes);
        pixels.dispose();
        #end
    }

    /** Return a retained, device-loss-safe tile for the editor title strip. */
    public static function getTitleBarTile():h2d.Tile {
        if (titleBarTile != null) return titleBarTile;

        var iconPixels = decodeClosestFrame(TITLE_BAR_ICON_SIZE);
        titleBarPixels = iconPixels.makeSquare(true);
        var texture = h3d.mat.Texture.fromPixels(titleBarPixels,
            h3d.mat.Texture.nativeFormat);
        titleBarTile = h2d.Tile.fromTexture(texture).sub(0, 0,
            iconPixels.width, iconPixels.height);
        if (iconPixels != titleBarPixels) iconPixels.dispose();
        texture.filter = h3d.mat.Data.Filter.Linear;
        texture.realloc = function() texture.uploadPixels(titleBarPixels);
        return titleBarTile;
    }

    static function decodeClosestFrame(preferredSize:Int):hxd.Pixels {
        var bytes = getSourceBytes();
        requireRange(bytes, 0, 6, "ICO header");
        if (readUInt16(bytes, 0) != 0 || readUInt16(bytes, 2) != 1) {
            throw "Boltspark icon is not a valid Windows ICO resource";
        }

        var count = readUInt16(bytes, 4);
        requireRange(bytes, 6, count * 16, "ICO directory");
        var selected:IconDirectoryEntry = null;
        var selectedDistance = 0x7FFFFFFF;
        for (index in 0...count) {
            var position = 6 + index * 16;
            var width = bytes.get(position);
            var height = bytes.get(position + 1);
            if (width == 0) width = 256;
            if (height == 0) height = 256;
            var entry:IconDirectoryEntry = {
                width: width,
                height: height,
                size: readInt32(bytes, position + 8),
                offset: readInt32(bytes, position + 12)
            };
            var distance = Std.int(Math.abs(width - preferredSize));
            if (selected == null || distance < selectedDistance
                    || (distance == selectedDistance && width > selected.width)) {
                selected = entry;
                selectedDistance = distance;
            }
        }
        if (selected == null) throw "Boltspark icon contains no image frames";
        requireRange(bytes, selected.offset, selected.size, "ICO image frame");
        return decodeFrame(bytes, selected);
    }

    static function decodeFrame(bytes:haxe.io.Bytes, entry:IconDirectoryEntry):hxd.Pixels {
        var offset = entry.offset;
        if (isPng(bytes, offset)) {
            var pngBytes = bytes.sub(offset, entry.size);
            var png = new format.png.Reader(new haxe.io.BytesInput(pngBytes)).read();
            var header = format.png.Tools.getHeader(png);
            var output = haxe.io.Bytes.alloc(header.width * header.height * 4);
            format.png.Tools.extract32(png, output, false);
            return new hxd.Pixels(header.width, header.height, output, hxd.PixelFormat.BGRA);
        }

        // ICO bitmap frames store a bottom-up BGRA XOR image followed by a
        // one-bit AND mask. Modern 32-bit frames carry their alpha in BGRA,
        // so only the XOR image is needed here.
        requireRange(bytes, offset, 40, "ICO bitmap header");
        var headerSize = readInt32(bytes, offset);
        var dibWidth = readInt32(bytes, offset + 4);
        var dibHeight = readInt32(bytes, offset + 8);
        var bitCount = readUInt16(bytes, offset + 14);
        var compression = readInt32(bytes, offset + 16);
        if (headerSize < 40 || bitCount != 32 || compression != 0) {
            throw 'Unsupported Boltspark ICO bitmap frame (${bitCount}-bit, compression ${compression})';
        }
        if (dibWidth != entry.width || Std.int(Math.abs(dibHeight)) < entry.height) {
            throw "Boltspark ICO bitmap dimensions do not match its directory entry";
        }

        var colorsUsed = readInt32(bytes, offset + 32);
        var paletteSize = colorsUsed > 0 ? colorsUsed * 4 : 0;
        var pixelOffset = offset + headerSize + paletteSize;
        var rowStride = ((entry.width * bitCount + 31) >> 5) << 2;
        requireRange(bytes, pixelOffset, rowStride * entry.height, "ICO bitmap pixels");

        var output = haxe.io.Bytes.alloc(entry.width * entry.height * 4);
        var bottomUp = dibHeight > 0;
        for (y in 0...entry.height) {
            var sourceY = bottomUp ? entry.height - 1 - y : y;
            output.blit(y * entry.width * 4, bytes,
                pixelOffset + sourceY * rowStride, entry.width * 4);
        }
        return new hxd.Pixels(entry.width, entry.height, output, hxd.PixelFormat.BGRA);
    }

    static function getSourceBytes():haxe.io.Bytes {
        if (sourceBytes == null) sourceBytes = hxd.Res.boltspark.entry.getBytes();
        return sourceBytes;
    }

    static function isPng(bytes:haxe.io.Bytes, offset:Int):Bool {
        return offset >= 0 && offset + 8 <= bytes.length
            && bytes.get(offset) == 0x89
            && bytes.get(offset + 1) == 0x50
            && bytes.get(offset + 2) == 0x4E
            && bytes.get(offset + 3) == 0x47
            && bytes.get(offset + 4) == 0x0D
            && bytes.get(offset + 5) == 0x0A
            && bytes.get(offset + 6) == 0x1A
            && bytes.get(offset + 7) == 0x0A;
    }

    static function requireRange(bytes:haxe.io.Bytes, offset:Int, length:Int,
            description:String):Void {
        if (offset < 0 || length < 0 || offset > bytes.length - length) {
            throw 'Boltspark icon has a truncated ${description}';
        }
    }

    static inline function readUInt16(bytes:haxe.io.Bytes, offset:Int):Int {
        return bytes.get(offset) | (bytes.get(offset + 1) << 8);
    }

    static inline function readInt32(bytes:haxe.io.Bytes, offset:Int):Int {
        return bytes.get(offset)
            | (bytes.get(offset + 1) << 8)
            | (bytes.get(offset + 2) << 16)
            | (bytes.get(offset + 3) << 24);
    }
}
