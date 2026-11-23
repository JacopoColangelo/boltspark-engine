param(
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\float-explorer-drop\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$layoutDir = Join-Path $localAppData 'Boltspark Engine'
$workspace = Join-Path $outputDir 'workspace'
$contentDir = Join-Path $workspace 'Content'
$artDir = Join-Path $contentDir 'Art'
$sourceDir = Join-Path $outputDir 'external'
$dropDir = Join-Path $outputDir 'drops'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
$projectFile = Join-Path $workspace 'Float Drop.boltproject'
$sceneFile = Join-Path (Join-Path $workspace 'Scenes') 'Main Scene.boltscene'
New-Item -ItemType Directory -Force $layoutDir | Out-Null
New-Item -ItemType Directory -Force (Join-Path $workspace 'Scenes') | Out-Null
New-Item -ItemType Directory -Force $artDir | Out-Null
New-Item -ItemType Directory -Force $sourceDir | Out-Null
New-Item -ItemType Directory -Force $dropDir | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

# Valid 4x4 PNG; import core copies bytes, thumbnails are covered elsewhere.
$pngBytes = [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAT0lEQVR42gFEALv/AFooAP9nbij/dLRQ/4H6eP8AjkCg/5uGyP+ozPD/tRIY/wDCWED/z55o/9zkkP/pKrj/APZw4P8Dtgj/EPww/x1CWP8zEye5c+CqJwAAAABJRU5ErkJggg==')
$sourceA = Join-Path $sourceDir 'Float One.png'
$sourceB = Join-Path $sourceDir 'Float Two.png'
[System.IO.File]::WriteAllBytes($sourceA, $pngBytes)
[System.IO.File]::WriteAllBytes($sourceB, $pngBytes)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$projectJson = @{
    version = 1
    id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    name = 'Float Drop'
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
    entities = @()
} | ConvertTo-Json -Depth 6 -Compress
[System.IO.File]::WriteAllText($sceneFile, $sceneJson, $utf8NoBom)

# Host the Asset Browser in its own HWND before the first draw.
$panel = { param([string]$id) @{ id = $id; key = $id; state = $null } }
$tab = { param([string[]]$ids) @{
    kind = 'tab'; active = 0
    panels = @($ids | ForEach-Object { & $panel $_ })
} }
$layout = @{
    version = 3
    bottomTab = 0
    closed = @()
    root = & $tab @('boltspark.hierarchy')
    floating = @(@{
        id = 7
        title = 'Asset Browser'
        x = 300
        y = 140
        width = 480
        height = 420
        minimized = $false
        root = & $tab @('boltspark.assets')
    })
}
[System.IO.File]::WriteAllText((Join-Path $layoutDir 'dock-layout.json'),
    ($layout | ConvertTo-Json -Depth 20))

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class BoltsparkFloatDropApi {
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static IntPtr LParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
    public static IntPtr[] FindWindows(uint pid, string className) {
        var result = new List<IntPtr>();
        EnumWindows((h, l) => {
            uint owner;
            GetWindowThreadProcessId(h, out owner);
            if (owner == pid) {
                var name = new StringBuilder(128);
                GetClassName(h, name, name.Capacity);
                if (name.ToString() == className) result.Add(h);
            }
            return true;
        }, IntPtr.Zero);
        return result.ToArray();
    }
}
"@

function Read-Log {
    return [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    $r = [IntPtr]::Zero
    [void][BoltsparkFloatDropApi]::SendMessageTimeout(
        $window, 0x0200, [IntPtr]::Zero,
        [BoltsparkFloatDropApi]::LParam($x, $y), 0, 5000, [ref]$r)
    [void][BoltsparkFloatDropApi]::SendMessageTimeout(
        $window, 0x0201, [IntPtr]1,
        [BoltsparkFloatDropApi]::LParam($x, $y), 0, 5000, [ref]$r)
    [void][BoltsparkFloatDropApi]::SendMessageTimeout(
        $window, 0x0202, [IntPtr]::Zero,
        [BoltsparkFloatDropApi]::LParam($x, $y), 0, 5000, [ref]$r)
    Start-Sleep -Milliseconds 180
}

function Send-FloatDrop([int]$index, [string]$panelId, [int]$x, [int]$y, [string[]]$paths) {
    $instruction = Join-Path $dropDir "float-drop-$index.txt"
    $content = "$panelId|$x;$y|" + ($paths -join '|')
    Set-Content -LiteralPath $instruction -Value $content -Encoding ascii
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        $log = Read-Log
    } while ($log -notmatch "\[probe\] float drop hook index=$index" -and
             [DateTime]::UtcNow -lt $deadline)
    if ($log -notmatch "\[probe\] float drop hook index=$index") {
        throw "Float drop instruction $index was not consumed. Log: $log"
    }
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$oldFloatDropDir = $env:BOLTSPARK_PROBE_FLOAT_DROP_DIR
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $env:BOLTSPARK_PROBE_FLOAT_DROP_DIR = $dropDir

    $process = Start-Process $runtime `
        -ArgumentList "boltspark.hl `"$projectFile`"" `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $floatWindow = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 150
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        $windows = [BoltsparkFloatDropApi]::FindWindows(
            [uint32]$process.Id, 'BoltSparkFloatPanel')
        if ($windows.Length -gt 0) {
            $floatWindow = $windows[0]
            break
        }
    }
    if ($floatWindow -eq [IntPtr]::Zero) { throw 'Floating Asset Browser HWND did not appear.' }

    $readyDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 150
        $startup = Read-Log
    } while ($startup -notmatch '\[probe\] asset browser asset row=' -and
             [DateTime]::UtcNow -lt $readyDeadline)
    if ($startup -notmatch '\[probe\] asset browser folder row=Art') {
        throw 'Floating browser did not list the seeded Art folder.'
    }

    # Discover the client y of the Art row by clicking candidate rows and
    # reading the navigation log (folder rows sit under the float header).
    $artY = -1
    foreach ($candidateY in 96, 118, 140, 162, 184) {
        $before = (Read-Log).Length
        Send-Click $floatWindow 60 $candidateY
        $slice = (Read-Log).Substring($before)
        if ($slice -match '\[probe\] asset browser navigate folder=Content/Art') {
            $artY = $candidateY
            break
        }
    }
    if ($artY -lt 0) { throw 'Could not locate the Content/Art folder row in the float.' }

    Send-FloatDrop 1 'boltspark.assets' 60 $artY @($sourceA, $sourceB)
    Start-Sleep -Milliseconds 700
    $log = Read-Log
    if ($log -notmatch '\[probe\] float file drop count=2 folder=Content/Art') {
        throw "Float drop did not resolve the Art folder. Log: $log"
    }
    if ($log -notmatch '\[probe\] import completed count=2 folder=Content/Art') {
        throw 'Float drop did not import both files into Content/Art.'
    }
    foreach ($name in @('Float One.png', 'Float Two.png')) {
        $copied = Join-Path $artDir $name
        if (-not (Test-Path $copied)) { throw "Float drop did not copy $name into Art." }
    }
    $manifest = Get-Content $projectFile -Raw | ConvertFrom-Json
    $textures = @($manifest.assets | Where-Object { $_.type -eq 'texture' })
    if ($textures.Count -ne 2 -or
        -not ($textures | Where-Object { $_.source -eq 'Content/Art/Float One.png' }) -or
        -not ($textures | Where-Object { $_.source -eq 'Content/Art/Float Two.png' })) {
        throw 'Manifest does not contain both float-dropped texture records.'
    }

    # Play mode must reject float drops without touching the manifest.
    $mainWindow = [IntPtr]::Zero
    foreach ($w in [BoltsparkFloatDropApi]::FindWindows([uint32]$process.Id, 'HL_WIN')) {
        $mainWindow = $w
        break
    }
    if ($mainWindow -eq [IntPtr]::Zero) { throw 'Main editor HWND not found.' }
    $r = [IntPtr]::Zero
    [void][BoltsparkFloatDropApi]::SendMessageTimeout(
        $mainWindow, 0x0100, [IntPtr]0x74, [IntPtr](1 -bor (0x3F -shl 16)), 0, 5000, [ref]$r)
    Start-Sleep -Milliseconds 350
    Send-FloatDrop 2 'boltspark.assets' 60 $artY @($sourceA)
    Start-Sleep -Milliseconds 350
    if ((Read-Log) -notmatch '\[probe\] float file drop rejected=play-mode') {
        throw 'Float drop was not rejected during Play mode.'
    }
    $final = Get-Content $projectFile -Raw | ConvertFrom-Json
    if (@($final.assets | Where-Object { $_.type -eq 'texture' }).Count -ne 2) {
        throw 'Rejected float drop changed the manifest.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    # Close the main window: WM_CLOSE on the float only re-docks that panel.
    [void][BoltsparkFloatDropApi]::PostMessage(
        $mainWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close cleanly after float drop probe.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Float drop probe wrote stderr; inspect $stderr."
    }

    Write-Host '[float-explorer-drop] Multi-file drop on a floating browser, folder placement, and Play-mode guard passed.' -ForegroundColor Green
    Write-Host "[float-explorer-drop] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    $env:BOLTSPARK_PROBE_FLOAT_DROP_DIR = $oldFloatDropDir
}
