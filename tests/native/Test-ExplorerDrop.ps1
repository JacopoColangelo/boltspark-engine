param(
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\explorer-drop\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$sourceDir = Join-Path $outputDir 'external'
$dropDir = Join-Path $outputDir 'drops'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
$projectFile = Join-Path $workspace 'Drop Demo.boltproject'
$sceneFile = Join-Path (Join-Path $workspace 'Scenes') 'Main Scene.boltscene'
$dropFolder = Join-Path (Join-Path $workspace 'Content') 'Art'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force (Join-Path $workspace 'Scenes') | Out-Null
New-Item -ItemType Directory -Force $dropFolder | Out-Null
New-Item -ItemType Directory -Force $sourceDir | Out-Null
New-Item -ItemType Directory -Force $dropDir | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

# Valid 4x4 PNG (format.png output); import core copies bytes, thumbnail
# decoding is asserted by Test-ImportFiles.ps1.
$pngBytes = [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAT0lEQVR42gFEALv/AFooAP9nbij/dLRQ/4H6eP8AjkCg/5uGyP+ozPD/tRIY/wDCWED/z55o/9zkkP/pKrj/APZw4P8Dtgj/EPww/x1CWP8zEye5c+CqJwAAAABJRU5ErkJggg==')
$sourceA = Join-Path $sourceDir 'Dropped One.png'
$sourceB = Join-Path $sourceDir 'Dropped Two.png'
[System.IO.File]::WriteAllBytes($sourceA, $pngBytes)
[System.IO.File]::WriteAllBytes($sourceB, $pngBytes)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$projectJson = @{
    version = 1
    id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    name = 'Drop Demo'
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
public static class BoltsparkDropApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Send-Message([IntPtr]$window, [uint32]$message,
        [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkDropApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw ('Message 0x{0:X} failed.' -f $message) }
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    Send-Message $window 0x0100 ([IntPtr]$virtualKey) ([IntPtr](1 -bor ($scanCode -shl 16)))
    Start-Sleep -Milliseconds 50
    Send-Message $window 0x0101 ([IntPtr]$virtualKey) ([IntPtr](0xC0000001 -bor ($scanCode -shl 16)))
    Start-Sleep -Milliseconds 80
}

function Send-Drop([int]$index, [int]$clientX, [int]$clientY, [string[]]$paths) {
    $instruction = Join-Path $dropDir "drop-$index.txt"
    $content = "$clientX;$clientY|" + ($paths -join '|')
    Set-Content -LiteralPath $instruction -Value $content -Encoding ascii
    $deadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 100
        $log = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
    } while ($log -notmatch "\[probe\] drop hook index=$index" -and
             [DateTime]::UtcNow -lt $deadline)
    if ($log -notmatch "\[probe\] drop hook index=$index") {
        throw "Drop instruction $index was not consumed by the editor."
    }
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$oldDropDir = $env:BOLTSPARK_PROBE_DROP_DIR
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $env:BOLTSPARK_PROBE_DROP_DIR = $dropDir

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
    [void][BoltsparkDropApi]::SetWindowPos(
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

    # Folder row "Content/Art" is index 2 in the tree (All, Content, Art).
    # The browser starts at contentY; rows begin at browser-local y=48.
    $rect = New-Object BoltsparkDropApi+RECT
    if (-not [BoltsparkDropApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed.'
    }
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $consoleX = 254
    $clientX = $consoleX + 60
    $clientY = $contentY + 48 + (2 * 22) + 11

    # Multi-file drop onto the Art folder row.
    Send-Drop 1 $clientX $clientY @($sourceA, $sourceB)
    Start-Sleep -Milliseconds 900

    $log = Get-Content $stdout -Raw
    if ($log -notmatch '\[probe\] os file drop count=2') {
        throw "Drop handler did not receive both files. Log: $log"
    }
    if ($log -notmatch '\[probe\] os file drop folder=Content/Art') {
        throw 'Explorer drop did not resolve the folder under the cursor.'
    }
    if ($log -notmatch '\[probe\] import completed count=2 folder=Content/Art') {
        throw 'Explorer drop did not import both files into the target folder.'
    }
    foreach ($name in @('Dropped One.png', 'Dropped Two.png')) {
        $copied = Join-Path $dropFolder $name
        if (-not (Test-Path $copied)) { throw "Dropped file missing: $copied" }
    }
    $manifest = Get-Content $projectFile -Raw | ConvertFrom-Json
    $textures = @($manifest.assets | Where-Object { $_.type -eq 'texture' })
    if ($textures.Count -ne 2 -or
        -not ($textures | Where-Object { $_.source -eq 'Content/Art/Dropped One.png' }) -or
        -not ($textures | Where-Object { $_.source -eq 'Content/Art/Dropped Two.png' })) {
        throw 'Manifest does not contain both dropped texture records.'
    }

    # Play mode must reject drops without touching the project.
    Send-Key $window 0x74 0x3F   # F5
    Start-Sleep -Milliseconds 400
    Send-Drop 2 $clientX $clientY @($sourceA)
    Start-Sleep -Milliseconds 400
    $playLog = Get-Content $stdout -Raw
    if ($playLog -notmatch '\[probe\] os file drop rejected=play-mode') {
        throw 'Explorer drop was not rejected while playing.'
    }
    Send-Key $window 0x75 0x40   # F6
    Start-Sleep -Milliseconds 400

    $finalManifest = Get-Content $projectFile -Raw | ConvertFrom-Json
    if (@($finalManifest.assets | Where-Object { $_.type -eq 'texture' }).Count -ne 2) {
        throw 'Rejected drop changed the manifest.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkDropApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close cleanly after Explorer drops.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Explorer drop probe wrote stderr; inspect $stderr."
    }

    Write-Host '[explorer-drop] Multi-file drop, folder placement, and Play-mode guard passed.' -ForegroundColor Green
    Write-Host "[explorer-drop] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    $env:BOLTSPARK_PROBE_DROP_DIR = $oldDropDir
}
