param(
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\material-editor\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force $workspace | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkMaterialApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Read-Log {
    return [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    $r = [IntPtr]::Zero
    [void][BoltsparkMaterialApi]::SendMessageTimeout(
        $window, 0x0200, [IntPtr]::Zero, [BoltsparkMaterialApi]::LP($x, $y), 0, 5000, [ref]$r)
    [void][BoltsparkMaterialApi]::SendMessageTimeout(
        $window, 0x0201, [IntPtr]1, [BoltsparkMaterialApi]::LP($x, $y), 0, 5000, [ref]$r)
    [void][BoltsparkMaterialApi]::SendMessageTimeout(
        $window, 0x0202, [IntPtr]::Zero, [BoltsparkMaterialApi]::LP($x, $y), 0, 5000, [ref]$r)
    Start-Sleep -Milliseconds 180
}

function Wait-For([string]$pattern, [int]$seconds, [string]$message) {
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        Start-Sleep -Milliseconds 120
        $log = Read-Log
    } while ($log -notmatch $pattern -and [DateTime]::UtcNow -lt $deadline)
    if ($log -notmatch $pattern) { throw "$message. Log: $log" }
    return $log
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$oldUntitled = $env:BOLTSPARK_PROBE_UNTITLED_DIR
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $workspace

    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $window = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 130
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    Wait-For '\[probe\] asset browser entries=' 12 'Browser never completed its initial scan' | Out-Null

    $rect = New-Object BoltsparkMaterialApi+RECT
    [void][BoltsparkMaterialApi]::GetClientRect($window, [ref]$rect)
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $consoleX = 254
    $consoleWidth = $rect.Right - 584
    $addX = $consoleX + $consoleWidth - 64 + 27
    $addY = $contentY + 13

    # Add -> Material is the fourth row (Scene, Folder, Import Asset..., Material).
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 45) ($contentY + 26 + 80)
    $created = Wait-For '\[probe\] material editor opened source=' 10 `
        'Add -> Material did not create and open a material'
    $sourceMatch = [regex]::Match($created,
        '(?m)^\[probe\] material editor opened source=(.+)$')
    if (-not $sourceMatch.Success) { throw 'Could not read the created material source.' }
    $materialSource = $sourceMatch.Groups[1].Value.Trim()
    if ($materialSource -notmatch '\.boltmaterial$') {
        throw "Unexpected material source: $materialSource"
    }
    if (-not (Test-Path (Join-Path $workspace $materialSource))) {
        throw "Material document was not written: $materialSource"
    }

    # Double-clicking the material tile must reopen the editor panel.
    # Return to the root, enter the Materials folder, then double-click tile 0.
    Send-Click $window ($consoleX + 60) ($contentY + 48 + 10)
    Start-Sleep -Milliseconds 250
    $tileY = $contentY + 26 + 4 + 40
    $tile0X = $consoleX + 118 + 8 + 44
    # Folder tiles sort first; the scratch root has Content and Materials.
    # The exact tile column depends on scroll state, so fall back to the root
    # grid: the material card is visible either way.
    Send-Click $window ($tile0X + 96) $tileY
    Send-Click $window ($tile0X + 96) $tileY
    Start-Sleep -Milliseconds 250
    foreach ($candidateX in $tile0X, $tile1X) {
        foreach ($candidateY in $tileY, ($tileY + 88)) {
            Send-Click $window $candidateX $candidateY
            Send-Click $window $candidateX $candidateY
            Start-Sleep -Milliseconds 350
        }
    }
    Start-Sleep -Milliseconds 600
    $openCount = ([regex]::Matches((Read-Log),
        '\[probe\] material editor opened source=')).Count
    if ($openCount -lt 2) {
        throw "Double-clicking the material tile did not reopen the Material Editor (opens=$openCount)."
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkMaterialApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close cleanly after material editor probe.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Material editor probe wrote stderr; inspect $stderr."
    }

    Write-Host "[material-editor] Created $materialSource, opened the editor, and reopened it on double-click." -ForegroundColor Green
    Write-Host "[material-editor] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $oldUntitled
}
