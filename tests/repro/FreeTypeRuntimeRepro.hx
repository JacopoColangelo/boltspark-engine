import freetype.heaps.FreeTypeFont;
import freetype.Library;
import sys.io.File;

/** Headless smoke test for exact-size runtime glyph creation and caching. */
class FreeTypeRuntimeRepro {
    static function main():Void {
        var library = new Library();
        var runtimeVersion = library.version;
        library.dispose();
        if (runtimeVersion != "2.14.3") {
            throw 'Expected FreeType 2.14.3, got ${runtimeVersion}';
        }

        var font = FreeTypeFont.dynamicFromBytes(
            File.getBytes("src/res/fonts/inter_regular.ttf"),
            13,
            {
                antiAliasing: true,
                atlasWidth: 64,
                chars: "A?",
                kerning: true,
                padding: 2,
                uploadTexture: false
            },
            "Inter runtime repro");

        // Omega is deliberately absent from the preload set. The first lookup
        // must rasterize and cache it; the second must return that same entry.
        var first = font.getChar("Ω".code);
        var second = font.getChar("Ω".code);
        if (first == null || first.width <= 0) throw "FreeType did not create Ω at runtime";
        if (first != second) throw "FreeType did not cache the generated Ω glyph";
        if (font.size != 13) throw 'Expected exact 13px font, got ${font.size}px';

        Sys.println('[freetype] exact-size dynamic glyph cache passed: '
            + 'runtime=${runtimeVersion} font=${font.name} '
            + 'size=${font.size}px omegaAdvance=${first.width}');
        font.dispose();
    }
}
