param(
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\asset-browser\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force (Join-Path $workspace 'Scenes') | Out-Null

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$projectFile = Join-Path $workspace 'Browser Demo.boltproject'
$projectJson = @{
    version = 1
    id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    name = 'Browser Demo'
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
[System.IO.File]::WriteAllText(
    (Join-Path $workspace 'Scenes\Main Scene.boltscene'), $sceneJson, $utf8NoBom)

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkAssetBrowserApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Send-Message([IntPtr]$window, [uint32]$message,
        [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkAssetBrowserApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) { throw ('Message 0x{0:X} failed.' -f $message) }
}

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [IntPtr]$buttons) {
    Send-Message $window $message $buttons `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Message $window 0x0200 ([IntPtr]::Zero) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
    Start-Sleep -Milliseconds 70
    Send-Message $window 0x0201 ([IntPtr]1) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
    Send-Message $window 0x0202 ([IntPtr]::Zero) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
    Start-Sleep -Milliseconds 180
}

function Send-RightClick([IntPtr]$window, [int]$x, [int]$y) {
    Send-Message $window 0x0200 ([IntPtr]::Zero) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
    Start-Sleep -Milliseconds 70
    Send-Message $window 0x0204 ([IntPtr]2) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
    Send-Message $window 0x0205 ([IntPtr]::Zero) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($x, $y))
    Start-Sleep -Milliseconds 200
}

function Send-Key([IntPtr]$window, [int]$virtualKey, [int]$scanCode) {
    Send-Message $window 0x0100 ([IntPtr]$virtualKey) ([IntPtr](1 -bor ($scanCode -shl 16)))
    Start-Sleep -Milliseconds 50
    Send-Message $window 0x0101 ([IntPtr]$virtualKey) ([IntPtr](0xC0000001 -bor ($scanCode -shl 16)))
    Start-Sleep -Milliseconds 60
}

function Send-Char([IntPtr]$window, [char]$character) {
    Send-Message $window 0x0102 ([IntPtr][int]$character) ([IntPtr]1)
    Start-Sleep -Milliseconds 60
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
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
    [void][BoltsparkAssetBrowserApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    $startupLog = Get-Content $stdout -Raw
    if ($startupLog -notmatch '\[console\] project: opened ') {
        throw 'Passing a .boltproject on the command line did not open it.'
    }
    if ($startupLog -notmatch '\[probe\] scene loaded entities=1') {
        throw 'Startup project did not rebuild its scene graph.'
    }

    # Geometry for the bottom dock, derived from the persisted layout defaults.
    $rect = New-Object BoltsparkAssetBrowserApi+RECT
    if (-not [BoltsparkAssetBrowserApi]::GetClientRect($window, [ref]$rect)) {
        throw 'GetClientRect failed.'
    }
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $consoleX = 254
    $consoleWidth = $rect.Right - 584
    # Grid tiles: 88x80 with an 8px gap, starting after the folder column.
    $tileY = $contentY + 26 + 4 + 40
    $tile0X = $consoleX + 118 + 8 + 44
    $tile1X = $tile0X + 96

    # Asset Browser is the first tab by default; clicking it is idempotent.
    Send-Click $window ($consoleX + 54) ($consoleY + 11)
    Start-Sleep -Milliseconds 400
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser entries=1') {
        throw 'Asset Browser tab did not list the seeded scene asset.'
    }

    # Add -> Scene: creates a distinct scene asset.
    $addX = $consoleX + $consoleWidth - 64 + 27
    $addY = $contentY + 13
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 33) ($contentY + 26 + 14)
    Start-Sleep -Milliseconds 700
    if ((Get-Content $stdout -Raw) -notmatch '\[console\] asset: created ') {
        throw 'Asset Browser Add -> Scene did not create a scene.'
    }
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser entries=2') {
        throw 'Asset Browser did not refresh after creating a scene.'
    }

    # Right-click the new scene tile, choose Rename, type a name, commit.
    Send-RightClick $window $tile1X $tileY
    Start-Sleep -Milliseconds 200
    # MenuDropdown clamps a 5-row context menu above the window bottom.
    $menuY = [Math]::Min($tileY, $rect.Bottom - (5 * 22 + 6) - 4)
    Send-Click $window ($tile1X + 40) ($menuY + 36)
    Start-Sleep -Milliseconds 200
    Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr]0x001D)
    Send-Key $window 0x41 0x1E   # Ctrl+A
    Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr]0xC01D0001)
    foreach ($character in 'Alpha Scene'.ToCharArray()) {
        Send-Char $window $character
    }
    Send-Key $window 0x0D 0x1C   # Enter commits inline rename
    Start-Sleep -Milliseconds 700

    if ((Get-Content $stdout -Raw) -notmatch '\[console\] asset: renamed ') {
        throw 'Asset Browser rename action did not run.'
    }
    if (Test-Path (Join-Path $workspace 'Scenes\New Scene.boltscene')) {
        throw 'Renamed asset left the old file behind.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Scenes\Alpha Scene.boltscene'))) {
        throw 'Renamed asset file was not written.'
    }
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser entries=2') {
        throw 'Asset Browser did not refresh after rename.'
    }

    # After rename the grid sorts alphabetically: Alpha Scene, Main Scene.
    Send-Click $window $tile1X $tileY
    Send-Click $window $tile1X $tileY
    Start-Sleep -Milliseconds 700
    $openLog = Get-Content $stdout -Raw
    if ($openLog -notmatch '\[probe\] asset browser open source=Scenes/Main Scene.boltscene') {
        throw 'Double-clicking an asset did not open it.'
    }
    if ($openLog -notmatch '\[console\] asset: opened ') {
        throw 'Asset open did not report a successful load.'
    }

    # Add -> Folder creates a real directory and refreshes the folder column.
    $foldersBefore = [regex]::Matches((Get-Content $stdout -Raw),
        '\[probe\] asset browser folders=').Count
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 150
    Send-Click $window ($addX + 33) ($contentY + 26 + 3 + 22 + 11)
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch '\[console\] folder: created ') {
        throw 'Asset Browser Add -> Folder did not create a folder.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Scenes\New Folder'))) {
        throw 'Created folder is missing on disk.'
    }
    if ([regex]::Matches((Get-Content $stdout -Raw),
            '\[probe\] asset browser folders=').Count -le $foldersBefore) {
        throw 'Asset Browser did not refresh after folder creation.'
    }

    # The created folder opens an inline name editor; Escape cancels it and F2
    # starts a fresh rename of the selected folder.
    Send-Key $window 0x1B 0x01
    Start-Sleep -Milliseconds 150
    Send-Key $window 0x71 0x3F   # F2
    Start-Sleep -Milliseconds 200
    Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr]0x001D)
    Send-Key $window 0x41 0x1E   # Ctrl+A
    Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr]0xC01D0001)
    foreach ($character in 'Vault'.ToCharArray()) {
        Send-Char $window $character
    }
    Send-Key $window 0x0D 0x1C   # Enter commits
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch '\[console\] folder: renamed ') {
        throw 'F2 did not rename the selected folder.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Scenes\Vault'))) {
        throw 'Renamed folder is missing on disk.'
    }
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser folder row=Vault depth=1') {
        throw 'Folder rows show paths or wrong nesting instead of folder names.'
    }

    # Copy an asset with Ctrl+C, select the Vault folder, paste with Ctrl+V.
    Send-Click $window $tile0X $tileY
    Start-Sleep -Milliseconds 150
    Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr]0x001D)
    Send-Key $window 0x43 0x1E   # Ctrl+C
    Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr]0xC01D0001)
    Start-Sleep -Milliseconds 200
    Send-Click $window ($consoleX + 60) ($contentY + 70 + 22 + 11)
    Start-Sleep -Milliseconds 150
    Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr]0x001D)
    Send-Key $window 0x56 0x2F   # Ctrl+V
    Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr]0xC01D0001)
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser paste ') {
        throw 'Ctrl+C / Ctrl+V did not paste the asset into the folder.'
    }

    # Enough assets force the grid to scroll.
    for ($i = 0; $i -lt 9; $i++) {
        Send-Click $window $addX $addY
        Start-Sleep -Milliseconds 100
        Send-Click $window ($addX + 33) ($contentY + 26 + 14)
        Start-Sleep -Milliseconds 220
    }
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser scrollable=true') {
        throw 'Asset Browser did not enable scrolling for a full grid.'
    }

    # Drag the selected tile onto the Scenes folder and choose Move Here.
    $folderRowY = $contentY + 70 + 11
    Send-Mouse $window 0x0200 $tile0X $tileY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    Send-Mouse $window 0x0201 $tile0X $tileY ([IntPtr]1)
    Send-Mouse $window 0x0200 ($consoleX + 60) $folderRowY ([IntPtr]1)
    Start-Sleep -Milliseconds 120
    Send-Mouse $window 0x0202 ($consoleX + 60) $folderRowY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 300
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] asset browser drop ') {
        throw 'Dragging an asset onto a folder did not offer a drop action.'
    }
    # Copy Here creates a uniquely named duplicate in the target folder.
    Send-Click $window ($consoleX + 100) ($folderRowY + 36)
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch '\[console\] asset: copied ') {
        throw 'Drop action did not copy the asset into the folder.'
    }

    # Collapsing Scenes hides the nested Vault row; expanding restores it.
    $beforeRows = [regex]::Matches((Get-Content $stdout -Raw),
        '\[probe\] asset browser folder row=Vault').Count
    Send-Click $window ($consoleX + 10) ($contentY + 70 + 22 + 11)
    Start-Sleep -Milliseconds 300
    $collapsedRows = [regex]::Matches((Get-Content $stdout -Raw),
        '\[probe\] asset browser folder row=Vault').Count
    if ($collapsedRows -le $beforeRows) { throw 'Collapsing a folder did not hide its children.' }
    Send-Click $window ($consoleX + 10) ($contentY + 70 + 22 + 11)
    Start-Sleep -Milliseconds 300
    $expandedRows = [regex]::Matches((Get-Content $stdout -Raw),
        '\[probe\] asset browser folder row=Vault').Count
    if ($expandedRows -le $collapsedRows) { throw 'Expanding a folder did not restore its children.' }

    [void][BoltsparkAssetBrowserApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after the Asset Browser probe.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Asset Browser probe wrote stderr; inspect $stderr."
    }

    Write-Host '[asset-browser] CLI project launch, asset scan, Add/Rename/Open passed.' -ForegroundColor Green
    Write-Host "[asset-browser] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
}
