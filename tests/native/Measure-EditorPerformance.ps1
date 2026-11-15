param(
    [double]$DurationMinutes = 15,
    [int]$SampleSeconds = 5,
    [switch]$NoResizeExercise,
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'
if ($DurationMinutes -lt 1) { throw 'DurationMinutes must be at least 1.' }
if ($SampleSeconds -lt 1) { throw 'SampleSeconds must be positive.' }

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDir = Join-Path $repoRoot "bin\test-results\performance\$stamp"
$localAppData = Join-Path $outputDir 'localappdata'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$csvPath = Join-Path $outputDir 'samples.csv'
$summaryPath = Join-Path $outputDir 'summary.json'
New-Item -ItemType Directory -Force $localAppData | Out-Null

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkPerformanceApi {
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

function Wait-Window([Diagnostics.Process]$process) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) { return $process.MainWindowHandle }
    }
    throw 'Editor HWND did not appear.'
}

function Read-GpuUtilization([int]$processId) {
    try {
        $counter = Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop
        $values = $counter.CounterSamples | Where-Object {
            $_.InstanceName -match "pid_$processId(_|$)"
        } | Select-Object -ExpandProperty CookedValue
        if ($null -eq $values) { return $null }
        # Different engines may execute concurrently. Sum is the conventional
        # Task-Manager-style process aggregate and is reported as observed,
        # without imposing a product budget during baseline capture.
        return [Math]::Round(($values | Measure-Object -Sum).Sum, 3)
    }
    catch {
        return $null
    }
}

$oldPerf = $env:BOLTSPARK_PERF_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$env:BOLTSPARK_PERF_PROBE = '1'
$env:LOCALAPPDATA = $localAppData
$process = $null
$samples = [Collections.Generic.List[object]]::new()
try {
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru
    $window = Wait-Window $process
    Start-Sleep -Seconds 2

    $start = [DateTime]::UtcNow
    $durationSeconds = $DurationMinutes * 60
    $lastWall = $start
    $process.Refresh()
    $lastCpuMs = $process.TotalProcessorTime.TotalMilliseconds
    $resizeToggle = $false

    while (([DateTime]::UtcNow - $start).TotalSeconds -lt $durationSeconds) {
        Start-Sleep -Seconds $SampleSeconds
        $now = [DateTime]::UtcNow
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited during performance capture with code $($process.ExitCode)." }
        $elapsed = ($now - $start).TotalSeconds
        $wallMs = ($now - $lastWall).TotalMilliseconds
        $cpuMs = $process.TotalProcessorTime.TotalMilliseconds
        $cpuPercent = if ($wallMs -le 0) { 0 } else {
            100 * ($cpuMs - $lastCpuMs) / $wallMs / [Environment]::ProcessorCount
        }
        $gpu = Read-GpuUtilization $process.Id
        $samples.Add([PSCustomObject]@{
            ElapsedSeconds = [Math]::Round($elapsed, 3)
            CpuPercent = [Math]::Round($cpuPercent, 3)
            GpuPercent = $gpu
            WorkingSetBytes = $process.WorkingSet64
            PrivateBytes = $process.PrivateMemorySize64
            Handles = $process.HandleCount
            Phase = if ($elapsed -le 60 -or $NoResizeExercise) { 'idle' } else { 'resize' }
        })
        $lastWall = $now
        $lastCpuMs = $cpuMs

        if (-not $NoResizeExercise -and $elapsed -gt 60) {
            $resizeToggle = -not $resizeToggle
            $width = if ($resizeToggle) { 1280 } else { 1440 }
            $height = if ($resizeToggle) { 800 } else { 900 }
            [void][BoltsparkPerformanceApi]::SetWindowPos(
                $window, [IntPtr]::Zero, 40, 40, $width, $height, 0x0004)
        }
    }

    [void][BoltsparkPerformanceApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close after performance capture.'
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) {
        throw "Editor exited with code $($process.ExitCode)."
    }
    if ((Get-Item $stderr).Length -ne 0) { throw "Performance run wrote stderr; inspect $stderr." }

    $samples | Export-Csv -NoTypeInformation -Encoding UTF8 $csvPath
    $oneMinute = $samples | Sort-Object {
        [Math]::Abs($_.ElapsedSeconds - 60)
    } | Select-Object -First 1
    $final = $samples | Select-Object -Last 1
    $idle = $samples | Where-Object Phase -eq 'idle'
    $resize = $samples | Where-Object Phase -eq 'resize'
    $gpuSamples = $samples | Where-Object { $null -ne $_.GpuPercent }
    $summary = [ordered]@{
        CapturedAt = (Get-Date).ToString('o')
        DurationMinutes = $DurationMinutes
        SampleSeconds = $SampleSeconds
        ProcessorCount = [Environment]::ProcessorCount
        OneMinute = $oneMinute
        Final = $final
        WorkingSetGrowthBytes = $final.WorkingSetBytes - $oneMinute.WorkingSetBytes
        PrivateGrowthBytes = $final.PrivateBytes - $oneMinute.PrivateBytes
        IdleAverageCpuPercent = [Math]::Round(($idle.CpuPercent | Measure-Object -Average).Average, 3)
        ResizeAverageCpuPercent = if ($resize.Count -eq 0) { $null } else { [Math]::Round(($resize.CpuPercent | Measure-Object -Average).Average, 3) }
        AverageGpuPercent = if ($gpuSamples.Count -eq 0) { $null } else { [Math]::Round(($gpuSamples.GpuPercent | Measure-Object -Average).Average, 3) }
        FrameTelemetry = @(Select-String -Path $stdout -Pattern '^\[perf\]') | ForEach-Object Line
    }
    $summary | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $summaryPath
    $summary | ConvertTo-Json -Depth 8
    Write-Host "[performance] Evidence: $outputDir" -ForegroundColor Green
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PERF_PROBE = $oldPerf
    $env:LOCALAPPDATA = $oldLocalAppData
}
