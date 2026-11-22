package boltspark.ui.render;

import freetype.Library;
import freetype.Face;
import haxe.io.Bytes;

private typedef GlyphInfo = {
    coverage:Bytes,
    width:Int,
    height:Int,
    left:Int,
    top:Int,
    advance:Int
}

/**
 * CPU glyph atlas for the raw-Win32 floating panel framebuffer.
 *
 * hldx/DX12 only owns the editor's HWND, so a float cannot render h2d.Text into
 * its own GDI surface. Instead FreeType coverage is composited directly into
 * the float's RGBA buffer. The buffer layout is top-down 32-bit BGRA, which is
 * what StretchDIBits/BI_RGB expects on Windows.
 */
class FloatGlyphAtlas {
    final library:Library;
    final face:Face;
    final glyphs:Map<Int, GlyphInfo> = new Map();
    public final size:Int;

    public function new(fontBytes:Bytes, pixelSize:Int) {
        size = pixelSize;
        library = new Library();
        face = library.loadFace(fontBytes);
        face.setPixelSize(0, pixelSize);
        for (code in 32...127) {
            var glyph = face.renderCodepoint(code);
            var bitmap = glyph.bitmap;
            var width = bitmap.width;
            var height = bitmap.rows;
            var coverage = Bytes.alloc(width * height);
            if (bitmap.pitch > 0 && bitmap.buffer != null) {
                for (y in 0...height) {
                    for (x in 0...width) {
                        coverage.set(y * width + x,
                            bitmap.buffer.getUI8(y * bitmap.pitch + x));
                    }
                }
            }
            glyphs.set(code, {
                coverage: coverage,
                width: width,
                height: height,
                left: glyph.bitmapLeft,
                top: glyph.bitmapTop,
                advance: Std.int(glyph.advanceX / 64)
            });
        }
    }

    /** Width in pixels of a single-line string under this atlas. */
    public function textWidth(text:String):Int {
        var width = 0;
        for (i in 0...text.length) {
            var glyph = glyphs.get(text.charCodeAt(i));
            width += glyph == null ? (size >> 1) + 1 : glyph.advance;
        }
        return width;
    }

    /**
     * Blend one text line into the BGRA buffer with row stride `stride` (pixels).
     * `baseline` is the text baseline measured from the top of the buffer and
     * `height` is the buffer height in pixels, used for vertical clipping.
     */
    public function drawLine(dest:Bytes, stride:Int, height:Int, text:String,
            x:Int, baseline:Int, color:Int):Void {
        var penX = x;
        var r = (color >> 16) & 0xFF;
        var g = (color >> 8) & 0xFF;
        var b = color & 0xFF;
        for (i in 0...text.length) {
            var glyph = glyphs.get(text.charCodeAt(i));
            if (glyph == null) {
                penX += (size >> 1) + 1;
                continue;
            }
            for (gy in 0...glyph.height) {
                var destY = baseline - glyph.top + gy;
                if (destY < 0 || destY >= height) continue;
                var coverageRow = gy * glyph.width;
                var destRow = destY * stride * 4;
                for (gx in 0...glyph.width) {
                    var destX = penX + glyph.left + gx;
                    if (destX < 0 || destX >= stride) continue;
                    var coverage = glyph.coverage.get(coverageRow + gx);
                    if (coverage <= 0) continue;
                    var alpha = coverage / 255;
                    var at = destRow + destX * 4;
                    dest.set(at, blend(dest.get(at), b, alpha));
                    dest.set(at + 1, blend(dest.get(at + 1), g, alpha));
                    dest.set(at + 2, blend(dest.get(at + 2), r, alpha));
                    dest.set(at + 3, 255);
                }
            }
            penX += glyph.advance;
        }
    }

    inline static function blend(background:Int, foreground:Int,
            alpha:Float):Int {
        return Std.int(background * (1 - alpha) + foreground * alpha);
    }
}
