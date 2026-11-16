param(
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = '3.52.0'
$cellSize = 16
$minimumSize = 6
$maximumSize = 16
$expectedAtlasSha256 = '775B63C2E56AC7693A1C7EBD5FBA54F5D485E702169BB8B9631A7BA1B11AAA52'
$sourceRoot = Join-Path $repoRoot "src\res\.tmp\tabler-icons\$version"
$outputPath = Join-Path $repoRoot 'src\res\icons\tabler_ui.png'

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
    @{ Column = 25; Variant = 'outline'; Name = 'file-description' }
)

Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $sourceRoot | Out-Null
New-Item -ItemType Directory -Force (Split-Path -Parent $outputPath) | Out-Null

$width = 26 * $cellSize
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
Write-Host "Generated $outputPath from Tabler Icons v$version." -ForegroundColor Green
