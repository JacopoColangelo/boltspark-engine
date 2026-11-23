param(
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\untitled-session\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$sourceDir = Join-Path $outputDir 'external'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
$sourcePng = Join-Path $sourceDir 'Scratch Texture.png'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force $workspace | Out-Null
New-Item -ItemType Directory -Force $sourceDir | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

# Valid 4x4 PNG produced by format.png in TextureCacheRepro.
$pngBytes = [Convert]::FromBase64String(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAT0lEQVR42gFEALv/AFooAP9nbij/dLRQ/4H6eP8AjkCg/5uGyP+ozPD/tRIY/wDCWED/z55o/9zkkP/pKrj/APZw4P8Dtgj/EPww/x1CWP8zEye5c+CqJwAAAABJRU5ErkJggg==')
[System.IO.File]::WriteAllBytes($sourcePng, $pngBytes)

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkUntitledApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Send([IntPtr]$window, [uint32]$message, [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    if ([BoltsparkUntitledApi]::SendMessageTimeout(
            $window, $message, $wparam, $lparam, 0, 5000, [ref]$result) -eq [IntPtr]::Zero) {
        throw ('Message 0x{0:X} failed.' -f $message)
    }
}

function Click([IntPtr]$window, [int]$x, [int]$y) {
    Send $window 0x0200 ([IntPtr]::Zero) ([BoltsparkUntitledApi]::LP($x, $y))
    Start-Sleep -Milliseconds 70
    Send $window 0x0201 ([IntPtr]1) ([BoltsparkUntitledApi]::LP($x, $y))
    Send $window 0x0202 ([IntPtr]::Zero) ([BoltsparkUntitledApi]::LP($x, $y))
    Start-Sleep -Milliseconds 180
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldOpen = $env:BOLTSPARK_PROBE_OPEN_FILE
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$oldUntitled = $env:BOLTSPARK_PROBE_UNTITLED_DIR
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_OPEN_FILE = $sourcePng
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $workspace

    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
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
    [void][BoltsparkUntitledApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 150
        $startupLog = Get-Content $stdout -Raw -ErrorAction SilentlyContinue
    } while ($startupLog -notmatch 'editor shell ready' -and
             [DateTime]::UtcNow -lt $readyDeadline)
    if ($startupLog -notmatch '\[probe\] asset browser folder row=Content depth=0') {
        throw 'Untitled browser did not show the scratch Content folder.'
    }

    $rect = New-Object BoltsparkUntitledApi+RECT
    [void][BoltsparkUntitledApi]::GetClientRect($window, [ref]$rect)
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $consoleX = 254
    $consoleWidth = $rect.Right - 584
    $addX = $consoleX + $consoleWidth - 64 + 27
    $addY = $contentY + 13

    # Add -> Folder (row 1) on the untitled session.
    Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Click $window ($addX + 33) ($contentY + 26 + 36)
    Start-Sleep -Milliseconds 500
    $folderLog = Get-Content $stdout -Raw
    if ($folderLog -notmatch '\[console\] folder: created Content/New Folder') {
        throw 'Untitled Add -> Folder did not create a scratch folder.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Content\New Folder'))) {
        throw 'Untitled folder was not written to the scratch workspace.'
    }

    # Return to the Content root so the import uses the default texture folder.
    Click $window ($consoleX + 60) ($contentY + 48 + 10)
    Start-Sleep -Milliseconds 300

    # Add -> Import Asset (row 2) on the untitled session.
    Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Click $window ($addX + 45) ($contentY + 26 + 58)
    Start-Sleep -Milliseconds 1000
    $importLog = Get-Content $stdout -Raw
    if ($importLog -notmatch '\[probe\] import completed count=1 folder=') {
        throw 'Untitled import did not complete.'
    }
    $copied = Join-Path $workspace 'Content\Scratch Texture.png'
    if (-not (Test-Path $copied)) {
        throw "Untitled import did not copy the file: $copied"
    }
    if ($importLog -notmatch '\[texture-cache\] tile path=.*Scratch Texture\.png') {
        throw 'Untitled imported texture did not produce a thumbnail.'
    }
    if (Get-ChildItem -LiteralPath $workspace -Filter '*.boltproject' -ErrorAction SilentlyContinue) {
        throw 'Untitled workflow unexpectedly created a project manifest.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkUntitledApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Untitled editor did not close cleanly.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Untitled probe wrote stderr; inspect $stderr."
    }

    Write-Host '[untitled-session] Folder creation, texture import, and thumbnails work without a project.' -ForegroundColor Green
    Write-Host "[untitled-session] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_OPEN_FILE = $oldOpen
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $oldUntitled
}
