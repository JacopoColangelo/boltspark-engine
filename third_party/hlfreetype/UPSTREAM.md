# hlfreetype upstream pin

- Project: `dtwotwo/hlfreetype`
- Version: 1.0.0
- Commit: `56c8aac44b1874f0e50c61d970fe8c171c3c5e70` (2026-11-09)
- Source archive SHA256: `1D8320D1CAF8C36A3FB9331E3EAC43341080395FDE0039AB3D8F0A2EEBBD57F2`
- License: MIT (`LICENSE`)

The vendored copy excludes upstream CI/editor configuration and tests. BoltSpark
has two small Heaps integration changes in `freetype/heaps/FreeTypeFont.hx`:

1. `FontChar.width` uses FreeType's pen advance without adding atlas padding or
   bitmap overhang, avoiding artificial tracking between editor glyphs.
2. Anti-aliased glyphs use the font face's native TrueType hinting with
   `TargetNormal`; forced light autohinting made Inter visibly too thin.

## FreeType pin

- Project: FreeType
- Version/tag: 2.14.3 / `VER-2-14-3`
- Commit: `0a0221a1347e2f1e07c395263540026e9a0aa7c7`
- Source archive SHA256: `A4C2B6F10C8C78013B410B1ED861485B1BE413F424BF9A6F92AABA844E13C934`
- Verified header SHA256: `FD45E7EE01C8F0F2419186D3FC9DD58E25CD866EF0C49F0B347C2D141665A364`
- License: FreeType License (`FreeType-LICENSE.txt`)

`tools/build.ps1 -InstallDependencies` installs the pinned FreeType source into
the ignored `vendor/freetype/` directory. CMake statically links it into the
project-local `freetype.hdll`; no system-wide FreeType installation is used.
