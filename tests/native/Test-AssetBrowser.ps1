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
    # Wait for the command-line project to finish loading instead of assuming
    # a fixed delay: the HWND appears before the scene graph is rebuilt.
    $startupDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 150
        $startupLog = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
        $loaded = $startupLog -match '\[console\] project: opened '
    } while (-not $loaded -and [DateTime]::UtcNow -lt $startupDeadline)

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

    # Folders now live in the Asset Panel, so the root shows the Scenes folder
    # tile first. Enter it before working with the scene assets inside.
    Send-Click $window $tile0X $tileY
    Send-Click $window $tile0X $tileY
    Start-Sleep -Milliseconds 300

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

    # Folder rows record navigation history; back/forward and breadcrumbs work.
    Send-Click $window ($consoleX + 60) ($contentY + 81)   # Scenes row
    Start-Sleep -Milliseconds 200
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser navigate folder=Scenes') {
        throw 'Clicking a folder row did not navigate.'
    }
    Send-Click $window ($consoleX + 15) ($contentY + 12)   # back arrow
    Start-Sleep -Milliseconds 200
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser history index=0') {
        throw 'Back arrow did not move through folder history.'
    }
    Send-Click $window ($consoleX + 39) ($contentY + 12)   # forward arrow
    Start-Sleep -Milliseconds 200
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser history index=1') {
        throw 'Forward arrow did not move through folder history.'
    }
    Send-Click $window ($consoleX + 100) ($contentY + 11)  # "Content" breadcrumb
    Start-Sleep -Milliseconds 200
    if ((Get-Content $stdout -Raw) -notmatch
            '(?m)\[probe\] asset browser navigate folder=\r?$') {
        throw 'Clicking the root breadcrumb did not return to Content.'
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
    # Add -> Folder creates at the Content root, never as an implicit subfolder.
    if (-not (Test-Path (Join-Path $workspace 'New Folder'))) {
        throw 'Created folder is missing from the Content root.'
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
    if (-not (Test-Path (Join-Path $workspace 'Vault'))) {
        throw 'Renamed root folder is missing on disk.'
    }
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser folder row=Vault depth=0') {
        throw 'Root folder rows show paths or wrong nesting instead of folder names.'
    }

    # Root lists folder tiles now; enter Scenes before copying one of its assets.
    Send-Click $window $tile0X $tileY
    Send-Click $window $tile0X $tileY
    Start-Sleep -Milliseconds 300

    # Copy an asset with Ctrl+C, select the Vault folder, paste with Ctrl+V.
    Send-Click $window $tile0X $tileY
    Start-Sleep -Milliseconds 150
    Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr]0x001D)
    Send-Key $window 0x43 0x1E   # Ctrl+C
    Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr]0xC01D0001)
    Start-Sleep -Milliseconds 200
    Send-Click $window ($consoleX + 60) ($contentY + 70 + 22 + 11)   # Vault row
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

    # The root now lists folders, so enter Scenes before dragging assets.
    Send-Click $window $tile0X $tileY
    Send-Click $window $tile0X $tileY
    Start-Sleep -Milliseconds 300

    # Dragging an asset onto a folder moves it immediately (no context menu).
    $folderRowY = $contentY + 58   # "All" root row (stable target)
    Send-Mouse $window 0x0200 $tile0X $tileY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 120
    Send-Mouse $window 0x0201 $tile0X $tileY ([IntPtr]1)
    Start-Sleep -Milliseconds 180
    Send-Mouse $window 0x0200 ($consoleX + 60) $folderRowY ([IntPtr]1)
    Start-Sleep -Milliseconds 220
    Send-Mouse $window 0x0202 ($consoleX + 60) $folderRowY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser drop source=.* mode=move') {
        throw 'Dragging an asset onto a folder did not move it directly.'
    }
    if ((Get-Content $stdout -Raw) -notmatch '\[console\] asset: moved ') {
        throw 'Direct drop did not report a move.'
    }

    # Ctrl+drop copies instead of moving. Synthetic drag timing is variable,
    # so retry a couple of times before treating it as a failure.
    $copyDone = $false
    for ($attempt = 0; $attempt -lt 3 -and -not $copyDone; $attempt++) {
        Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr]0x001D)
        Send-Mouse $window 0x0200 $tile0X $tileY ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 80
        Send-Mouse $window 0x0201 $tile0X $tileY ([IntPtr]1)
        Send-Mouse $window 0x0200 ($consoleX + 60) $folderRowY ([IntPtr]1)
        Start-Sleep -Milliseconds 120
        Send-Mouse $window 0x0202 ($consoleX + 60) $folderRowY ([IntPtr]::Zero)
        Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr]0xC01D0001)
        Start-Sleep -Milliseconds 600
        $copyDone = (Get-Content $stdout -Raw) -match
            '\[probe\] asset browser drop source=.* mode=copy'
    }
    if (-not $copyDone) {
        throw 'Ctrl+dragging an asset did not offer a copy.'
    }

    # Collapse Scenes so its assets do not push Vault out of the short tree.
    Send-Click $window ($consoleX + 10) ($contentY + 81)
    Start-Sleep -Milliseconds 200

    # Nested folders are explicit: right-click Vault -> New... -> Folder.
    $vaultRowY = $contentY + 70 + 22 + 11
    Send-RightClick $window ($consoleX + 60) $vaultRowY
    $submenuY = [Math]::Min($vaultRowY, $rect.Bottom - (7 * 22 + 6) - 4)
    Send-Click $window ($consoleX + 100) ($submenuY + 3 + 11)   # New... row
    Send-Click $window (($consoleX + 60) + 168 + 40) ($submenuY + 17)   # Folder
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser folder row=New Folder depth=1') {
        throw 'New Subfolder did not create a nested folder row.'
    }

    # Collapsing Vault hides its nested row; expanding restores it.
    $logBefore = (Get-Content $stdout -Raw).Length
    Send-Click $window ($consoleX + 10) $vaultRowY
    Start-Sleep -Milliseconds 300
    $collapsedSlice = (Get-Content $stdout -Raw).Substring($logBefore)
    if ($collapsedSlice -match '\[probe\] asset browser folder row=New Folder') {
        throw 'Collapsing a folder did not hide its children.'
    }
    $logBeforeExpand = (Get-Content $stdout -Raw).Length
    Send-Click $window ($consoleX + 10) $vaultRowY
    Start-Sleep -Milliseconds 300
    $expandedSlice = (Get-Content $stdout -Raw).Substring($logBeforeExpand)
    if ($expandedSlice -notmatch '\[probe\] asset browser folder row=New Folder') {
        throw 'Expanding a folder did not restore its children.'
    }

    # Folder rows are draggable too: drag Vault onto Scenes to nest it.
    $scenesRowY = $contentY + 70 + 11
    Send-Mouse $window 0x0200 ($consoleX + 60) $vaultRowY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    Send-Mouse $window 0x0201 ($consoleX + 60) $vaultRowY ([IntPtr]1)
    Send-Mouse $window 0x0200 ($consoleX + 60) $scenesRowY ([IntPtr]1)
    Start-Sleep -Milliseconds 120
    Send-Mouse $window 0x0202 ($consoleX + 60) $scenesRowY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 600
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser folder drop source=Vault folder=Scenes') {
        throw 'Dragging a folder onto another folder did not reparent it.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Scenes\Vault'))) {
        throw 'Dropped folder is missing from its new parent.'
    }
    # Vault is nested under the collapsed Scenes folder; expand it again so the
    # nested New Folder row is visible for the delete probe.
    Send-Click $window ($consoleX + 10) ($contentY + 81)
    Start-Sleep -Milliseconds 200

    # Right-click empty space opens the Add menu without using the + button.
    Send-RightClick $window ($consoleX + 190) ($contentY + 13)   # empty toolbar space
    Start-Sleep -Milliseconds 250
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] asset browser empty menu folder=') {
        throw 'Right-clicking empty space did not open the Add menu.'
    }
    # Any left-click outside the rows must dismiss the open menu.
    $closesBefore = [regex]::Matches((Get-Content $stdout -Raw),
        '\[probe\] menu close').Count
    Send-Click $window ($consoleX + 150) ($contentY + 13)
    Start-Sleep -Milliseconds 250
    if ([regex]::Matches((Get-Content $stdout -Raw),
            '\[probe\] menu close').Count -le $closesBefore) {
        throw 'Left-clicking outside a context menu did not dismiss it.'
    }

    # Wheel over the grid scrolls down with a positive delta.
    $scrollBefore = [regex]::Matches((Get-Content $stdout -Raw),
        '\[probe\] asset browser scroll=').Count
    Send-Message $window 0x020A ([IntPtr](-120 -shl 16)) `
        ([BoltsparkAssetBrowserApi]::MakeLParam($tile0X, $tileY))
    Start-Sleep -Milliseconds 300
    $scrollLog = (Get-Content $stdout -Raw)
    if ([regex]::Matches($scrollLog, '\[probe\] asset browser scroll=').Count -le $scrollBefore) {
        throw 'Wheel over the asset grid did not scroll.'
    }
    if ($scrollLog -notmatch '\[probe\] asset browser scroll=0\.(0*[1-9])') {
        throw 'Wheel down did not move the scroll position forward.'
    }

    # Delete key routes to the Asset Browser for both assets and folders.
    # Folders sort first in the panel, so the first asset is the second tile.
    Send-Click $window $tile1X $tileY
    Start-Sleep -Milliseconds 150
    Send-Key $window 0x2E 0x53   # Delete
    Start-Sleep -Milliseconds 500
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] confirm Delete assets=yes') {
        throw 'Delete key did not act on the selected asset.'
    }
    Send-Click $window ($consoleX + 60) ($contentY + 125)   # nested New Folder row
    Start-Sleep -Milliseconds 150
    Send-Key $window 0x2E 0x53   # Delete
    Start-Sleep -Milliseconds 500
    if ((Get-Content $stdout -Raw) -notmatch
            '\[probe\] confirm Delete folder=yes') {
        throw 'Delete key did not act on the selected folder.'
    }
    if ((Get-Content $stdout -Raw) -notmatch '\[console\] folder: deleted ') {
        throw 'Delete key did not actually remove the selected folder.'
    }

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
