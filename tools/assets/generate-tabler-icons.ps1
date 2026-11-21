param(
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$version = '3.52.0'
$cellSize = 16
$minimumSize = 6
$maximumSize = 16
$expectedAtlasSha256 = 'F07E185C74DE57BA2BF0811E3DE24697533738DB5DDC56AE55BE39B9165DB542'
$sourceRoot = Join-Path $repoRoot "src\res\.tmp\tabler-icons\$version"
$outputPath = Join-Path $repoRoot 'src\res\icons\tabler_ui.png'
# A separate, larger alpha mask for asset-browser scene thumbnails: the UI
# atlas only rasterizes 6-16px, which is too small for a preview tile.
$sceneThumbPath = Join-Path $repoRoot 'src\res\icons\scene_thumb.png'
$expectedSceneThumbSha256 = 'BA235FB9EDC6BEF12847DAF7F3CA1926C451170265EBE1AC722682CC8AD6B0C2'
# A matching 64px folder mask keeps asset-browser folder tiles crisp; the 16px
# atlas glyph would have to be upscaled and look blurry.
$folderThumbPath = Join-Path $repoRoot 'src\res\icons\folder_thumb.png'
$expectedFolderThumbSha256 = '4BC891ECED4A5B17AA991C3CC82A6D1FF72D6D775534CAE4BEAB515013AB2A3A'

# Columns deliberately match UiIconKind's integer values. Column zero is the
# transparent `None` entry. Every other entry comes from the official Tabler
# Icons PNG package generated from the corresponding 24x24 SVG.
$icons = @(
    @{ Column = 1;  Variant = 'outline'; Name = 'plus' },
    @{ Column = 2;  Variant = 'outline'; Name = 'trash' },
    @{ Column = 3;  Variant = 'outline'; Name = 'cube' },
    @{ Column = 4;  Variant = 'outline'; Name = 'search' },
    @{ Column = 5;  Variant = 'outline'; Name = 'player-play' },
    @{ Column = 6;  Variant = 'outline'; Name = 'player-pause' },
    @{ Column = 7;  Variant = 'outline'; Name = 'player-stop' },
    @{ Column = 8;  Variant = 'outline'; Name = 'arrows-move' },
    @{ Column = 9;  Variant = 'outline'; Name = 'rotate-clockwise' },
    @{ Column = 10; Variant = 'outline'; Name = 'arrows-diagonal-2' },
    @{ Column = 11; Variant = 'outline'; Name = 'chevron-down' },
    @{ Column = 12; Variant = 'outline'; Name = 'chevron-right' },
    @{ Column = 13; Variant = 'outline'; Name = 'terminal-2' },
    @{ Column = 14; Variant = 'outline'; Name = 'adjustments-horizontal' },
    @{ Column = 15; Variant = 'outline'; Name = 'hierarchy-2' },
    @{ Column = 16; Variant = 'outline'; Name = 'x' },
    @{ Column = 17; Variant = 'outline'; Name = 'grid-4x4' },
    @{ Column = 18; Variant = 'outline'; Name = 'dots' },
    @{ Column = 19; Variant = 'outline'; Name = 'chevron-up' },
    @{ Column = 20; Variant = 'filled';  Name = 'point' },
    @{ Column = 21; Variant = 'outline'; Name = 'link' },
    @{ Column = 22; Variant = 'outline'; Name = 'unlink' },
    @{ Column = 23; Variant = 'outline'; Name = 'restore' },
    @{ Column = 24; Variant = 'outline'; Name = 'folder' },
    @{ Column = 25; Variant = 'outline'; Name = 'file-description' },
    @{ Column = 26; Variant = 'outline'; Name = 'arrows-sort' },
    @{ Column = 27; Variant = 'outline'; Name = 'filter' },
    @{ Column = 28; Variant = 'outline'; Name = 'settings' },
    @{ Column = 29; Variant = 'outline'; Name = 'list' },
    @{ Column = 30; Variant = 'outline'; Name = 'table' },
    @{ Column = 31; Variant = 'outline'; Name = 'file' },
    @{ Column = 32; Variant = 'outline'; Name = 'box' },
    @{ Column = 33; Variant = 'outline'; Name = 'star' },
    @{ Column = 34; Variant = 'outline'; Name = 'arrow-left' },
    @{ Column = 35; Variant = 'outline'; Name = 'arrow-right' },
    @{ Column = 36; Variant = 'outline'; Name = 'arrow-up' },
    @{ Column = 37; Variant = 'outline'; Name = 'eye' },
    @{ Column = 38; Variant = 'outline'; Name = 'eye-off' },
    @{ Column = 39; Variant = 'outline'; Name = 'camera' },
    @{ Column = 40; Variant = 'outline'; Name = 'check' },
    @{ Column = 41; Variant = 'outline'; Name = 'minus' },
    @{ Column = 42; Variant = 'outline'; Name = 'eraser' }
)

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $sourceRoot | Out-Null
New-Item -ItemType Directory -Force (Split-Path -Parent $outputPath) | Out-Null

$width = 43 * $cellSize
$height = ($maximumSize - $minimumSize + 1) * $cellSize
$pixelFormat = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
$atlas = New-Object System.Drawing.Bitmap($width, $height, $pixelFormat)
$graphics = [System.Drawing.Graphics]::FromImage($atlas)

try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

    foreach ($icon in $icons) {
        $fileName = "$($icon.Variant)-$($icon.Name).png"
        $sourcePath = Join-Path $sourceRoot $fileName
        if ($Refresh -or -not (Test-Path $sourcePath)) {
            $mirrors = @(
                "https://cdn.jsdelivr.net/npm/@tabler/icons-png@$version/icons/$($icon.Variant)/$($icon.Name).png",
                "https://unpkg.com/@tabler/icons-png@$version/icons/$($icon.Variant)/$($icon.Name).png"
            )
            Write-Host "[tabler] Downloading $($icon.Variant)/$($icon.Name)" -ForegroundColor Cyan
            $downloaded = $false
            foreach ($uri in $mirrors) {
                try {
                    Invoke-WebRequest -Uri $uri -OutFile $sourcePath -TimeoutSec 30
                    $downloaded = $true
                    break
                } catch {
                    Write-Host "[tabler] Mirror failed: $($_.Exception.Message)" -ForegroundColor Yellow
                    if (Test-Path $sourcePath) { Remove-Item -LiteralPath $sourcePath -Force }
                }
            }
            if (-not $downloaded) {
                throw "Could not download Tabler source $($icon.Variant)/$($icon.Name)."
            }
        }

        $source = [System.Drawing.Image]::FromFile($sourcePath)
        try {
            if ($source.Width -ne 240 -or $source.Height -ne 240) {
                throw "Unexpected Tabler source dimensions for ${fileName}: $($source.Width)x$($source.Height)."
            }
            foreach ($size in $minimumSize..$maximumSize) {
                $destination = New-Object System.Drawing.Rectangle(
                    ($icon.Column * $cellSize),
                    (($size - $minimumSize) * $cellSize),
                    $size,
                    $size)
                $sourceRectangle = New-Object System.Drawing.Rectangle(
                    0, 0, $source.Width, $source.Height)
                $graphics.DrawImage($source, $destination, $sourceRectangle,
                    [System.Drawing.GraphicsUnit]::Pixel)
            }
        }
        finally {
            $source.Dispose()
        }
    }
}
finally {
    $graphics.Dispose()
}

# Tabler's package uses black RGB. BoltUI needs a white alpha mask so the
# h2d.Bitmap color transform can tint every icon without a custom shader.
for ($y = 0; $y -lt $atlas.Height; $y++) {
    for ($x = 0; $x -lt $atlas.Width; $x++) {
        $pixel = $atlas.GetPixel($x, $y)
        if ($pixel.A -ne 0) {
            $atlas.SetPixel($x, $y,
                [System.Drawing.Color]::FromArgb($pixel.A, 255, 255, 255))
        }
    }
}

$temporaryOutput = "$outputPath.tmp"
try {
    $atlas.Save($temporaryOutput, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $atlas.Dispose()
}
$actualAtlasSha256 = (Get-FileHash $temporaryOutput -Algorithm SHA256).Hash
if ($actualAtlasSha256 -ne $expectedAtlasSha256) {
    Remove-Item -LiteralPath $temporaryOutput -Force
    throw "Generated Tabler atlas hash mismatch: expected $expectedAtlasSha256, got $actualAtlasSha256."
}
Move-Item -LiteralPath $temporaryOutput -Destination $outputPath -Force

# Dedicated 64px scene thumbnail from Tabler `outline/photo` (a framed
# landscape, the closest analog to an Unreal-style level thumbnail).
$sceneSourceName = 'outline-photo.png'
$sceneSourcePath = Join-Path $sourceRoot $sceneSourceName
if ($Refresh -or -not (Test-Path $sceneSourcePath)) {
    $sceneMirrors = @(
        "https://cdn.jsdelivr.net/npm/@tabler/icons-png@$version/icons/outline/photo.png",
        "https://unpkg.com/@tabler/icons-png@$version/icons/outline/photo.png"
    )
    $sceneDownloaded = $false
    foreach ($uri in $sceneMirrors) {
        try {
            Invoke-WebRequest -Uri $uri -OutFile $sceneSourcePath -TimeoutSec 30
            $sceneDownloaded = $true
            break
        } catch {
            Write-Host "[tabler] Mirror failed: $($_.Exception.Message)" -ForegroundColor Yellow
            if (Test-Path $sceneSourcePath) { Remove-Item -LiteralPath $sceneSourcePath -Force }
        }
    }
    if (-not $sceneDownloaded) {
        throw "Could not download Tabler source outline/photo."
    }
}
$sceneThumbSize = 64
$sceneThumb = New-Object System.Drawing.Bitmap(
    $sceneThumbSize, $sceneThumbSize, $pixelFormat)
$sceneGraphics = [System.Drawing.Graphics]::FromImage($sceneThumb)
try {
    $sceneGraphics.Clear([System.Drawing.Color]::Transparent)
    $sceneGraphics.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sceneGraphics.PixelOffsetMode =
        [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $sceneSource = [System.Drawing.Image]::FromFile($sceneSourcePath)
    try {
        if ($sceneSource.Width -ne 240 -or $sceneSource.Height -ne 240) {
            throw "Unexpected Tabler source dimensions for ${sceneSourceName}: $($sceneSource.Width)x$($sceneSource.Height)."
        }
        $sceneGraphics.DrawImage($sceneSource,
            (New-Object System.Drawing.Rectangle(0, 0, $sceneThumbSize, $sceneThumbSize)),
            (New-Object System.Drawing.Rectangle(0, 0, $sceneSource.Width, $sceneSource.Height)),
            [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally { $sceneSource.Dispose() }
}
finally { $sceneGraphics.Dispose() }
for ($y = 0; $y -lt $sceneThumbSize; $y++) {
    for ($x = 0; $x -lt $sceneThumbSize; $x++) {
        $pixel = $sceneThumb.GetPixel($x, $y)
        if ($pixel.A -ne 0) {
            $sceneThumb.SetPixel($x, $y,
                [System.Drawing.Color]::FromArgb($pixel.A, 255, 255, 255))
        }
    }
}
$sceneTemporaryOutput = "$sceneThumbPath.tmp"
try {
    $sceneThumb.Save($sceneTemporaryOutput, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally { $sceneThumb.Dispose() }
$actualSceneThumbSha256 = (Get-FileHash $sceneTemporaryOutput -Algorithm SHA256).Hash
if ($actualSceneThumbSha256 -ne $expectedSceneThumbSha256) {
    Remove-Item -LiteralPath $sceneTemporaryOutput -Force
    throw "Generated scene thumbnail hash mismatch: expected $expectedSceneThumbSha256, got $actualSceneThumbSha256."
}
Move-Item -LiteralPath $sceneTemporaryOutput -Destination $sceneThumbPath -Force

# Dedicated 64px folder thumbnail from Tabler `outline/folder`.
$folderSourceName = 'outline-folder.png'
$folderSourcePath = Join-Path $sourceRoot $folderSourceName
if ($Refresh -or -not (Test-Path $folderSourcePath)) {
    $folderMirrors = @(
        "https://cdn.jsdelivr.net/npm/@tabler/icons-png@$version/icons/outline/folder.png",
        "https://unpkg.com/@tabler/icons-png@$version/icons/outline/folder.png"
    )
    $folderDownloaded = $false
    foreach ($uri in $folderMirrors) {
        try {
            Invoke-WebRequest -Uri $uri -OutFile $folderSourcePath -TimeoutSec 30
            $folderDownloaded = $true
            break
        } catch {
            Write-Host "[tabler] Mirror failed: $($_.Exception.Message)" -ForegroundColor Yellow
            if (Test-Path $folderSourcePath) { Remove-Item -LiteralPath $folderSourcePath -Force }
        }
    }
    if (-not $folderDownloaded) {
        throw "Could not download Tabler source outline/folder."
    }
}
$folderThumbSize = 64
$folderThumb = New-Object System.Drawing.Bitmap(
    $folderThumbSize, $folderThumbSize, $pixelFormat)
$folderGraphics = [System.Drawing.Graphics]::FromImage($folderThumb)
try {
    $folderGraphics.Clear([System.Drawing.Color]::Transparent)
    $folderGraphics.InterpolationMode =
        [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $folderGraphics.PixelOffsetMode =
        [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $folderSource = [System.Drawing.Image]::FromFile($folderSourcePath)
    try {
        if ($folderSource.Width -ne 240 -or $folderSource.Height -ne 240) {
            throw "Unexpected Tabler source dimensions for ${folderSourceName}: $($folderSource.Width)x$($folderSource.Height)."
        }
        $folderGraphics.DrawImage($folderSource,
            (New-Object System.Drawing.Rectangle(0, 0, $folderThumbSize, $folderThumbSize)),
            (New-Object System.Drawing.Rectangle(0, 0, $folderSource.Width, $folderSource.Height)),
            [System.Drawing.GraphicsUnit]::Pixel)
    }
    finally { $folderSource.Dispose() }
}
finally { $folderGraphics.Dispose() }
for ($y = 0; $y -lt $folderThumbSize; $y++) {
    for ($x = 0; $x -lt $folderThumbSize; $x++) {
        $pixel = $folderThumb.GetPixel($x, $y)
        if ($pixel.A -ne 0) {
            $folderThumb.SetPixel($x, $y,
                [System.Drawing.Color]::FromArgb($pixel.A, 255, 255, 255))
        }
    }
}
$folderTemporaryOutput = "$folderThumbPath.tmp"
try {
    $folderThumb.Save($folderTemporaryOutput, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally { $folderThumb.Dispose() }
$actualFolderThumbSha256 = (Get-FileHash $folderTemporaryOutput -Algorithm SHA256).Hash
if ($actualFolderThumbSha256 -ne $expectedFolderThumbSha256) {
    Remove-Item -LiteralPath $folderTemporaryOutput -Force
    throw "Generated folder thumbnail hash mismatch: expected $expectedFolderThumbSha256, got $actualFolderThumbSha256."
}
Move-Item -LiteralPath $folderTemporaryOutput -Destination $folderThumbPath -Force
Write-Host "Generated $outputPath, $sceneThumbPath, and $folderThumbPath from Tabler Icons v$version." -ForegroundColor Green
