param([int]$TimeoutSeconds = 30)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$outputDir = Join-Path $repoRoot 'bin\test-results\device-reset'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
New-Item -ItemType Directory -Force $outputDir | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkDeviceResetApi {
    [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

$oldProbe = $env:BOLTSPARK_DEVICE_RESET_PROBE
$env:BOLTSPARK_DEVICE_RESET_PROBE = '1'
$process = $null
try {
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Milliseconds 200
        $process.Refresh()
        if ($process.HasExited) { throw 'Editor exited during the device-reset probe.' }
        $log = if (Test-Path $stdout) { Get-Content $stdout -Raw } else { '' }
    } while ($log -notmatch '\[device-reset\] DX12 context recreated' -and
        [DateTime]::UtcNow -lt $deadline)

    if ($log -notmatch '\[device-reset\] forcing Heaps DX12 context-loss path') {
        throw 'The DX12 driver reset was never requested.'
    }
    if ($log -notmatch '\[device-reset\] DX12 context recreated and scene resources restored') {
        throw 'The DX12 context-loss callback did not complete before timeout.'
    }
    if ($process.MainWindowHandle -eq [IntPtr]::Zero) {
        throw 'Editor HWND disappeared after DX12 context recreation.'
    }
    $result = [IntPtr]::Zero
    $responsive = [BoltsparkDeviceResetApi]::SendMessageTimeout(
        $process.MainWindowHandle, 0, [IntPtr]::Zero, [IntPtr]::Zero,
        0x0002, 3000, [ref]$result)
    if ($responsive -eq [IntPtr]::Zero) { throw 'Editor was unresponsive after context recreation.' }
    Start-Sleep -Seconds 1
    if ((Get-Item $stderr).Length -ne 0) { throw "Device-reset probe wrote stderr; inspect $stderr." }

    [void][BoltsparkDeviceResetApi]::PostMessage(
        $process.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit(10000)) { throw 'Editor did not close after device-reset probe.' }
    Write-Host '[device-reset] Heaps DX12 forced context-loss/reset path passed.' -ForegroundColor Green
    Write-Host '[device-reset] This validates Heaps recreation, not a physical DXGI device-removal event.'
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_DEVICE_RESET_PROBE = $oldProbe
}
