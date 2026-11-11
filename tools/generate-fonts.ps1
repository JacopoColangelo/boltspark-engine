$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot 'src\res\fonts'
New-Item -ItemType Directory -Force $outDir | Out-Null

# Printable ASCII plus useful editor symbols (middle dot, degree, plus-minus, en/em dash, ellipsis, bullet, arrows)
$chars = New-Object System.Collections.Generic.List[char]
for ($code = 32; $code -le 126; $code++) {
    $chars.Add([char]$code)
}
foreach ($extra in @(0x00B0, 0x00B1, 0x00B7, 0x00D7, 0x2013, 0x2014, 0x2022, 0x2026)) {
    $chars.Add([char]$extra)
}

function Build-BMFont {
    param(
        [string]$BaseName,
        [string]$FontPath,
        [float]$PixelSize,
        [System.Drawing.FontStyle]$FontStyle,
        [int]$AtlasWidth = 512,
        [int]$AtlasHeight = 256
    )

    $privateFonts = New-Object System.Drawing.Text.PrivateFontCollection
    $privateFonts.AddFontFile((Resolve-Path $FontPath))
    $family = $privateFonts.Families[0]
    $FamilyName = $family.Name
    $font = New-Object System.Drawing.Font($family, $PixelSize, $FontStyle, [System.Drawing.GraphicsUnit]::Pixel)
    $emHeight = [double]$family.GetEmHeight($FontStyle)
    $cellAscent = [double]$family.GetCellAscent($FontStyle)
    $cellDescent = [double]$family.GetCellDescent($FontStyle)
    $lineSpacing = [double]$family.GetLineSpacing($FontStyle)

    $ascentPx = [int][Math]::Ceiling($PixelSize * $cellAscent / $emHeight)
    $descentPx = [int][Math]::Ceiling($PixelSize * $cellDescent / $emHeight)
    $lineHeightPx = [int][Math]::Ceiling($PixelSize * $lineSpacing / $emHeight)
    if ($lineHeightPx -lt ($ascentPx + $descentPx)) {
        $lineHeightPx = $ascentPx + $descentPx
    }

    $scratch = New-Object System.Drawing.Bitmap(128, 128, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $scratchGfx = [System.Drawing.Graphics]::FromImage($scratch)
    $scratchGfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $scratchGfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $fmt = [System.Drawing.StringFormat]::GenericTypographic
    $fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces

    $atlas = New-Object System.Drawing.Bitmap($AtlasWidth, $AtlasHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $atlasGfx = [System.Drawing.Graphics]::FromImage($atlas)
    $atlasGfx.Clear([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $atlasGfx.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $atlasGfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 255))

    $curX = 2
    $curY = 2
    $rowH = 0
    $glyphEntries = New-Object System.Collections.Generic.List[PSObject]

    foreach ($ch in $chars) {
        $code = [int]$ch
        $str = [string]$ch

        # Measure exact typographic advance using flanking H characters to avoid GDI+ overhang clipping
        $pairWidth = $scratchGfx.MeasureString("H${str}H", $font, 1000, $fmt).Width
        $hhWidth = $scratchGfx.MeasureString("HH", $font, 1000, $fmt).Width
        $advance = [int][Math]::Round($pairWidth - $hhWidth)
        if ($advance -lt 1) { $advance = [int][Math]::Round($PixelSize * 0.35) }

        if ($code -eq 32) {
            $glyphEntries.Add([PSCustomObject]@{
                Id = 32; X = 0; Y = 0; Width = 0; Height = 0; XOffset = 0; YOffset = 0; XAdvance = $advance
            })
            continue
        }

        # Render onto scratch pad with generous margin, then find tight non-zero alpha bounding box
        $scratchGfx.Clear([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
        $drawOriginX = 16
        $drawOriginY = 16
        $scratchGfx.DrawString($str, $font, $whiteBrush, [float]$drawOriginX, [float]$drawOriginY, $fmt)

        $minX = 128; $minY = 128; $maxX = -1; $maxY = -1
        for ($py = 0; $py -lt 96; $py++) {
            for ($px = 0; $px -lt 96; $px++) {
                $c = $scratch.GetPixel($px, $py)
                if ($c.A -gt 0) {
                    if ($px -lt $minX) { $minX = $px }
                    if ($py -lt $minY) { $minY = $py }
                    if ($px -gt $maxX) { $maxX = $px }
                    if ($py -gt $maxY) { $maxY = $py }
                }
            }
        }

        if ($maxX -lt $minX) {
            $glyphEntries.Add([PSCustomObject]@{
                Id = $code; X = 0; Y = 0; Width = 0; Height = 0; XOffset = 0; YOffset = 0; XAdvance = $advance
            })
            continue
        }

        $gw = ($maxX - $minX + 1)
        $gh = ($maxY - $minY + 1)
        $xOffset = $minX - $drawOriginX
        $yOffset = $minY - $drawOriginY

        if (($curX + $gw + 2) -gt $AtlasWidth) {
            $curX = 2
            $curY += $rowH + 2
            $rowH = 0
        }
        if (($curY + $gh + 2) -gt $AtlasHeight) {
            throw "Font atlas overflow for $BaseName at char $code"
        }

        for ($py = 0; $py -lt $gh; $py++) {
            for ($px = 0; $px -lt $gw; $px++) {
                $pix = $scratch.GetPixel($minX + $px, $minY + $py)
                if ($pix.A -gt 0) {
                    # Pure white RGB with smooth coverage alpha so Heaps vertex color tinting is crisp and halo-free
                    $atlas.SetPixel($curX + $px, $curY + $py, [System.Drawing.Color]::FromArgb([int]$pix.A, 255, 255, 255))
                }
            }
        }

        $glyphEntries.Add([PSCustomObject]@{
            Id = $code
            X = $curX
            Y = $curY
            Width = $gw
            Height = $gh
            XOffset = $xOffset
            YOffset = $yOffset
            XAdvance = $advance
        })

        $curX += $gw + 2
        if ($gh -gt $rowH) { $rowH = $gh }
    }

    $pngName = "$BaseName.png"
    $pngPath = Join-Path $outDir $pngName
    $fntPath = Join-Path $outDir "$BaseName.fnt"

    $atlas.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0"?>')
    [void]$sb.AppendLine("<font>")
    [void]$sb.AppendLine("  <info face=`"$FamilyName`" size=`"$([int][Math]::Round($PixelSize))`" bold=`"$(if ($FontStyle -band [System.Drawing.FontStyle]::Bold) { 1 } else { 0 })`" italic=`"0`" charset=`"`" unicode=`"1`" stretchH=`"100`" smooth=`"1`" aa=`"1`" padding=`"0,0,0,0`" spacing=`"2,2`" outline=`"0`"/>")
    [void]$sb.AppendLine("  <common lineHeight=`"$lineHeightPx`" base=`"$ascentPx`" scaleW=`"$AtlasWidth`" scaleH=`"$AtlasHeight`" pages=`"1`" packed=`"0`"/>")
    [void]$sb.AppendLine("  <pages>")
    [void]$sb.AppendLine("    <page id=`"0`" file=`"$pngName`"/>")
    [void]$sb.AppendLine("  </pages>")
    [void]$sb.AppendLine("  <chars count=`"$($glyphEntries.Count)`">")
    foreach ($g in $glyphEntries) {
        [void]$sb.AppendLine("    <char id=`"$($g.Id)`" x=`"$($g.X)`" y=`"$($g.Y)`" width=`"$($g.Width)`" height=`"$($g.Height)`" xoffset=`"$($g.XOffset)`" yoffset=`"$($g.YOffset)`" xadvance=`"$($g.XAdvance)`" page=`"0`" chnl=`"15`"/>")
    }
    [void]$sb.AppendLine("  </chars>")
    [void]$sb.AppendLine("  <kernings count=`"0`"/>")
    [void]$sb.AppendLine("</font>")

    [System.IO.File]::WriteAllText($fntPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))

    $whiteBrush.Dispose()
    $atlasGfx.Dispose()
    $atlas.Dispose()
    $scratchGfx.Dispose()
    $scratch.Dispose()
    $font.Dispose()
    $privateFonts.Dispose()

    Write-Host "Generated $BaseName ($FamilyName ${PixelSize}px, lineHeight=$lineHeightPx, base=$ascentPx)" -ForegroundColor Green
}

$fontSource = Join-Path $PSScriptRoot 'font-source'
# Inter is loaded directly from TTF by the runtime FreeType cache. The console
# intentionally retains its existing fixed mono atlas, regenerated here.
Build-BMFont -BaseName 'mono_12' -FontPath (Join-Path $fontSource 'JetBrainsMono.ttf') -PixelSize 12 -FontStyle ([System.Drawing.FontStyle]::Regular) -AtlasWidth 256 -AtlasHeight 256
