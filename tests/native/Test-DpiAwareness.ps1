param([int]$TimeoutSeconds = 20)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$outputDir = Join-Path $repoRoot 'bin\test-results\dpi-awareness'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkDpiProbeApi {
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("shcore.dll")] public static extern int GetProcessDpiAwareness(IntPtr process, out int awareness);
}
"@

$oldProbe = $env:BOLTSPARK_DPI_PROBE
$env:BOLTSPARK_DPI_PROBE = '1'
$process = $null
try {
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw 'Editor exited before DPI inspection.' }
    } while ($process.MainWindowHandle -eq [IntPtr]::Zero -and [DateTime]::UtcNow -lt $deadline)
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    Start-Sleep -Milliseconds 500

    $dpi = [BoltsparkDpiProbeApi]::GetDpiForWindow($process.MainWindowHandle)
    $awareness = 0
    $awarenessResult = [BoltsparkDpiProbeApi]::GetProcessDpiAwareness(
        $process.Handle, [ref]$awareness)
    if ($awarenessResult -ne 0) { throw "GetProcessDpiAwareness failed: $awarenessResult" }
    if ($awareness -lt 1) { throw "Editor process is not DPI-aware (awareness=$awareness)." }
    if ($dpi -lt 96) { throw "GetDpiForWindow returned an invalid DPI: $dpi." }

    [void][BoltsparkDpiProbeApi]::PostMessage(
        $process.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after DPI probe.'
    }
    if ((Get-Item $stderr).Length -ne 0) { throw "DPI probe wrote stderr; inspect $stderr." }
    $line = Select-String -Path $stdout -Pattern '^\[dpi\] displayScale='
    if ($null -eq $line) { throw 'Editor did not report the hldx display scale.' }

    $expectedScale = $dpi / 96.0
    $reported = [double]([regex]::Match($line.Line, 'displayScale=([0-9.]+)').Groups[1].Value)
    if ([Math]::Abs($reported - $expectedScale) -gt 0.02) {
        throw "hldx display scale $reported disagrees with Win32 DPI scale $expectedScale."
    }
    $result = [ordered]@{
        Dpi = $dpi
        Scale = $reported
        ProcessAwareness = $awareness
        Note = 'This validates the current monitor only; physical cross-monitor DPI transitions remain a manual hardware gate.'
    }
    $result | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $outputDir 'result.json')
    $result | ConvertTo-Json
    Write-Host "[dpi] Current-monitor awareness and hldx scale agreement passed." -ForegroundColor Green
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_DPI_PROBE = $oldProbe
}
