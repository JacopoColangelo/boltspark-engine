param(
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\import-files\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$sourceDir = Join-Path $outputDir 'external'
$pickerDir = Join-Path $outputDir 'picker'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
$projectFile = Join-Path $workspace 'Import Demo.boltproject'
$sceneFile = Join-Path (Join-Path $workspace 'Scenes') 'Main Scene.boltscene'
$sourcePng = Join-Path $sourceDir 'External Texture.png'
$sourceJpg = Join-Path $sourceDir 'Metal049C_2K-Color.jpg'
$sourceJpg2 = Join-Path $sourceDir 'Metal049C_2K-Roughness.jpg'
$texturesDir = Join-Path $workspace 'Content'
$importedPng = Join-Path $texturesDir 'External Texture.png'
$importedJpg = Join-Path $texturesDir 'Metal049C_2K-Color.jpg'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force (Join-Path $workspace 'Scenes') | Out-Null
New-Item -ItemType Directory -Force $sourceDir | Out-Null
New-Item -ItemType Directory -Force $pickerDir | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

# GDI+ is used both to synthesize the JPG fixture and for PrintWindow evidence.
Add-Type -AssemblyName System.Drawing

# A real 4x4 PNG (generated with format.png) so thumbnail decoding is exercised.
$pngBytes = [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAT0lEQVR42gFEALv/AFooAP9nbij/dLRQ/4H6eP8AjkCg/5uGyP+ozPD/tRIY/wDCWED/z55o/9zkkP/pKrj/APZw4P8Dtgj/EPww/x1CWP8zEye5c+CqJwAAAABJRU5ErkJggg==')
[System.IO.File]::WriteAllBytes($sourcePng, $pngBytes)
# Mirror the reported case: a real JPG whose name is not just "texture.png".
$jpgBitmap = New-Object System.Drawing.Bitmap 4, 4
$jpgGraphics = [System.Drawing.Graphics]::FromImage($jpgBitmap)
$jpgGraphics.Clear([System.Drawing.Color]::FromArgb(255, 120, 80, 200))
$jpgGraphics.Dispose()
$jpgBitmap.Save($sourceJpg, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$jpgBitmap.Save($sourceJpg2, [System.Drawing.Imaging.ImageFormat]::Jpeg)
$jpgBitmap.Dispose()

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$projectJson = @{
    version = 1
    id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    name = 'Import Demo'
    defaultSceneId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    assets = @(@{
        id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        type = 'scene'
        source = 'Scenes/Main Scene.boltscene'
    })
} | ConvertTo-Json -Depth 5 -Compress
[System.IO.File]::WriteAllText($projectFile, $projectJson, $utf8NoBom)
$sceneJson = @{
    version = 1
    id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    name = 'Main Scene'
    entities = @(@{
        id = 'cccccccccccccccccccccccccccccccc'
        name = 'Seeded Cube'
        parentId = $null
        transform = @{ position = @(0,0,0); rotation = @(0,0,0); scale = @(1,1,1) }
        components = @()
    })
} | ConvertTo-Json -Depth 6 -Compress
[System.IO.File]::WriteAllText($sceneFile, $sceneJson, $utf8NoBom)

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkImportApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Send-Message([IntPtr]$window, [uint32]$message,
        [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkImportApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw ('Message 0x{0:X} failed.' -f $message) }
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Message $window 0x0200 ([IntPtr]::Zero) ([BoltsparkImportApi]::MakeLParam($x, $y))
    Start-Sleep -Milliseconds 70
    Send-Message $window 0x0201 ([IntPtr]1) ([BoltsparkImportApi]::MakeLParam($x, $y))
    Send-Message $window 0x0202 ([IntPtr]::Zero) ([BoltsparkImportApi]::MakeLParam($x, $y))
    Start-Sleep -Milliseconds 180
}

function Send-Pick([int]$index, [string[]]$paths) {
    $answer = Join-Path $pickerDir "pick-$index.txt"
    Set-Content -LiteralPath $answer -Value ($paths -join '|') -Encoding ascii
}

function Send-DoubleClick([IntPtr]$window, [int]$x, [int]$y) {
    Send-Click $window $x $y
    Send-Click $window $x $y
    Start-Sleep -Milliseconds 250
}

function Save-Screenshot([IntPtr]$window, [string]$path) {
    $rect = New-Object BoltsparkImportApi+RECT
    if (-not [BoltsparkImportApi]::GetWindowRect($window, [ref]$rect)) {
        throw 'GetWindowRect failed.'
    }
    $bitmap = New-Object System.Drawing.Bitmap(($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top))
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    if (-not [BoltsparkImportApi]::PrintWindow($window, $hdc, 2)) {
        $graphics.ReleaseHdc($hdc)
        throw 'PrintWindow failed.'
    }
    $graphics.ReleaseHdc($hdc)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldOpen = $env:BOLTSPARK_PROBE_OPEN_FILE
$oldMultiOpen = $env:BOLTSPARK_PROBE_OPEN_FILES
$oldPickerDir = $env:BOLTSPARK_PROBE_PICKER_DIR
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_OPEN_FILE = $sourcePng
    $env:BOLTSPARK_PROBE_OPEN_FILES = ''
    $env:BOLTSPARK_PROBE_PICKER_DIR = $pickerDir
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    Send-Pick 1 @($sourcePng)

    $process = Start-Process $runtime `
        -ArgumentList "boltspark.hl `"$projectFile`"" `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $window = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    [void][BoltsparkImportApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)

    $startupDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 150
        $startupLog = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
    } while ($startupLog -notmatch '\[console\] project: opened ' -and
             [DateTime]::UtcNow -lt $startupDeadline)
    if ($startupLog -notmatch '\[console\] project: opened ') {
        throw 'Passing a .boltproject on the command line did not open it.'
    }

    # Same bottom-dock geometry used by Test-AssetBrowser.ps1.
    $rect = New-Object BoltsparkImportApi+RECT
    if (-not [BoltsparkImportApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed.'
    }
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $consoleX = 254
    $consoleWidth = $rect.Right - 584

    Send-Click $window ($consoleX + 54) ($consoleY + 11)   # Asset Browser tab
    Start-Sleep -Milliseconds 400
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser entries=1') {
        throw 'Asset Browser did not list the seeded scene asset.'
    }

    # Add menu: Scene (row 0), Folder (row 1), Import Asset (row 2).
    $addX = $consoleX + $consoleWidth - 64 + 27
    $addY = $contentY + 13
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 45) ($contentY + 26 + 58)
    Start-Sleep -Milliseconds 900

    $log = Get-Content $stdout -Raw
    if ($log -notmatch '\[probe\] asset browser import request folder=') {
        throw 'Import Asset command did not reach the Asset Browser callback.'
    }
    if ($log -notmatch '\[probe\] file dialog open title="Import Texture"') {
        throw 'Import command did not reach the native file-picker call site.'
    }
    if ($log -notmatch '\[probe\] import picker exts=.*jpg') {
        throw 'Import picker filter does not offer JPG textures.'
    }
    if ($log -notmatch 'spec=\*\.png;\*\.jpg;\*\.jpeg;\*\.tga') {
        throw 'Import picker did not pass the image-only filter spec to the native dialog.'
    }
    if ($log -notmatch '\[probe\] import completed count=1 folder=') {
        throw 'Import command did not report a successful import.'
    }
    if (-not (Test-Path $importedPng)) {
        throw "Imported texture was not copied to the project: $importedPng"
    }
    $copied = [System.IO.File]::ReadAllBytes($importedPng)
    if ($copied.Length -ne $pngBytes.Length) {
        throw "Imported texture size mismatch: $($copied.Length) vs $($pngBytes.Length)."
    }
    $manifest = Get-Content $projectFile -Raw | ConvertFrom-Json
    $textures = @($manifest.assets | Where-Object { $_.type -eq 'texture' })
    if ($textures.Count -ne 1 -or $textures[0].source -ne 'Content/External Texture.png') {
        throw 'Manifest does not contain the imported texture record.'
    }
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser entries=2') {
        throw 'Asset Browser did not refresh after import.'
    }

    # Navigate into Content so the imported texture card is rendered.
    $tileY = $contentY + 26 + 4 + 40
    $tile0X = $consoleX + 118 + 8 + 44
    Send-DoubleClick $window $tile0X $tileY       # Content folder
    Start-Sleep -Milliseconds 900
    $thumbLog = Get-Content $stdout -Raw
    if ($thumbLog -notmatch '\[probe\] asset browser navigate folder=Content') {
        throw 'Could not navigate to the Content folder.'
    }
    if ($thumbLog -notmatch '\[texture-cache\] tile path=.*External Texture\.png') {
        throw 'Imported texture thumbnail was not decoded and uploaded.'
    }

    # Second import from the same menu, this time a real JPG named like the
    # reported Metal049C_2K maps. The picker must offer and accept it.
    Send-Pick 2 @($sourceJpg)
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 45) ($contentY + 26 + 58)
    Start-Sleep -Milliseconds 1000
    $jpgLog = Get-Content $stdout -Raw
    $dialogs = [regex]::Matches($jpgLog, '\[probe\] file dialog open title="Import Texture"').Count
    if ($dialogs -lt 2) {
        throw 'Second import did not reach the native file-picker call site.'
    }
    if (-not (Test-Path $importedJpg)) {
        throw "JPG import was not copied into the project: $importedJpg"
    }
    $afterJpg = Get-Content $projectFile -Raw | ConvertFrom-Json
    $jpgRecords = @($afterJpg.assets | Where-Object {
        $_.type -eq 'texture' -and $_.source -eq 'Content/Metal049C_2K-Color.jpg'
    })
    if ($jpgRecords.Count -ne 1) {
        throw 'JPG import did not create exactly one texture manifest record.'
    }
    if ($jpgLog -notmatch '\[texture-cache\] tile path=.*Metal049C_2K-Color\.jpg') {
        throw 'Imported JPG thumbnail was not decoded and uploaded.'
    }

    # Multi-select path: one Import command with a whole PBR texture set.
    Send-Pick 3 @($sourceJpg, $sourceJpg2)
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 45) ($contentY + 26 + 58)
    Start-Sleep -Milliseconds 1200
    $multiLog = Get-Content $stdout -Raw
    if ($multiLog -notmatch '\[probe\] file dialog open title="Import Texture" choice=[^\r\n]*\|[^\r\n]*') {
        throw 'Multi-file picker did not receive more than one selected path.'
    }
    if ($multiLog -notmatch '\[probe\] import completed count=2 folder=') {
        throw 'Multi-file import did not copy both selected textures in one command.'
    }
    foreach ($name in @('Metal049C_2K-Color 2.jpg', 'Metal049C_2K-Roughness.jpg')) {
        if (-not (Test-Path (Join-Path $texturesDir $name))) {
            throw "Multi-file import missing copied texture: $name"
        }
    }
    $finalManifest = Get-Content $projectFile -Raw | ConvertFrom-Json
    $finalTextures = @($finalManifest.assets | Where-Object { $_.type -eq 'texture' })
    if ($finalTextures.Count -ne 4) {
        throw "Expected four texture records after multi-file import, got $($finalTextures.Count)."
    }

    $screenshot = Join-Path $outputDir 'imported-texture-thumbnail.png'
    Save-Screenshot $window $screenshot
    if (-not (Test-Path $screenshot) -or (Get-Item $screenshot).Length -eq 0) {
        throw 'PrintWindow thumbnail evidence was not written.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkImportApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close cleanly after import.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Import probe wrote stderr; inspect $stderr."
    }

    Write-Host '[import-files] Add -> Import Asset copied PNG and JPG textures (multi-extension picker), registered both records, decoded both thumbnails, and refreshed the browser.' -ForegroundColor Green
    Write-Host "[import-files] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_OPEN_FILE = $oldOpen
    $env:BOLTSPARK_PROBE_OPEN_FILES = $oldMultiOpen
    $env:BOLTSPARK_PROBE_PICKER_DIR = $oldPickerDir
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
}
