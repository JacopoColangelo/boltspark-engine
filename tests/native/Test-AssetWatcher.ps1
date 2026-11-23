param(
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\asset-watcher\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$contentDir = Join-Path $workspace 'Content'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force $contentDir | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

# Seed one visible file so the first browser scan has a known entry count.
Set-Content -LiteralPath (Join-Path $contentDir 'Seed Note.txt') -Value 'seed' -Encoding ascii

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkWatcherApi {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

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
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }

    # Wait for the watcher's baseline before writing anything externally, so
    # the change is a real edge rather than part of the first snapshot.
    $baselineDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 120
        $baselineLog = [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
    } while ($baselineLog -notmatch '\[probe\] watcher baseline established' -and
             [DateTime]::UtcNow -lt $baselineDeadline)
    if ($baselineLog -notmatch '\[probe\] watcher baseline established') {
        throw "Asset watcher never established its baseline. Log: $baselineLog"
    }

    # Initial browser scan gives the baseline entry count.
    $startup = ''
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(12)
    do {
        Start-Sleep -Milliseconds 120
        $startup = [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
    } while ($startup -notmatch '\[probe\] asset browser entries=' -and
             [DateTime]::UtcNow -lt $readyDeadline)
    $seedMatch = [regex]::Match($startup, '\[probe\] asset browser entries=(\d+)')
    if (-not $seedMatch.Success) {
        throw "Browser never completed its initial scan. Log: $startup"
    }
    $seedCount = [int]$seedMatch.Groups[1].Value

    # External top-level change: the watcher must refresh without any editor UI.
    Set-Content -LiteralPath (Join-Path $contentDir 'External Note.txt') -Value 'external' -Encoding ascii
    $log = ''
    $waitDeadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 120
        $log = [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
        $signals = ([regex]::Matches($log, '\[watcher\] external asset change detected')).Count
        $counts = [regex]::Matches($log, '\[probe\] asset browser entries=(\d+)')
        $entries = 0
        if ($counts.Count -gt 0) { $entries = [int]$counts[$counts.Count - 1].Groups[1].Value }
    } while (($signals -lt 1 -or $entries -le $seedCount) -and
             [DateTime]::UtcNow -lt $waitDeadline)
    if ($signals -lt 1 -or $entries -le $seedCount) {
        throw "External file write did not refresh the browser ($seedCount -> $entries). Log: $log"
    }
    $topCount = $entries

    # Nested change: a new folder plus file verifies recursive re-arming.
    $subDir = Join-Path $contentDir 'External Sub'
    New-Item -ItemType Directory -Force $subDir | Out-Null
    Start-Sleep -Milliseconds 400
    Set-Content -LiteralPath (Join-Path $subDir 'Nested Note.txt') -Value 'nested' -Encoding ascii
    $waitDeadline = [DateTime]::UtcNow.AddSeconds(8)
    do {
        Start-Sleep -Milliseconds 120
        $log = [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
        $signals = ([regex]::Matches($log, '\[watcher\] external asset change detected')).Count
        $counts = [regex]::Matches($log, '\[probe\] asset browser entries=(\d+)')
        $entries = 0
        if ($counts.Count -gt 0) { $entries = [int]$counts[$counts.Count - 1].Groups[1].Value }
    } while (($signals -lt 2 -or $entries -le $topCount) -and
             [DateTime]::UtcNow -lt $waitDeadline)
    if ($signals -lt 2 -or $entries -le $topCount) {
        throw "Nested folder write did not refresh the browser ($topCount -> $entries). Log: $log"
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkWatcherApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close cleanly after watcher probe.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Asset watcher probe wrote stderr; inspect $stderr."
    }

    Write-Host "[asset-watcher] External top-level and nested changes refreshed the browser ($seedCount -> $topCount -> $entries)." -ForegroundColor Green
    Write-Host "[asset-watcher] Evidence: $outputDir"
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
