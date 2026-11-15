$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class MoveLoopProbeNative {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessage(IntPtr h, uint message, IntPtr wparam, ref RECT lparam);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessage(IntPtr h, uint message, IntPtr wparam, IntPtr lparam);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT rect);
}
"@
function Measure-Timers([IntPtr]$window, [int]$count) {
  $times = [Collections.Generic.List[double]]::new()
  for ($i = 0; $i -lt $count; $i++) {
    Start-Sleep -Milliseconds 20
    $timer = [Diagnostics.Stopwatch]::StartNew()
    [void][MoveLoopProbeNative]::SendMessage($window, 0x0113, [IntPtr]::Zero, [IntPtr]::Zero)
    $timer.Stop()
    $times.Add($timer.Elapsed.TotalMilliseconds)
  }
  return ,$times.ToArray()
}
Get-Process Boltspark -ErrorAction SilentlyContinue | Stop-Process -Force
$repo = Split-Path -Parent $PSScriptRoot
$release = Join-Path $repo 'release'
$process = Start-Process (Join-Path $release 'Boltspark.exe') -WorkingDirectory $release -PassThru
try {
  for ($i = 0; $i -lt 100; $i++) { Start-Sleep -Milliseconds 100; $process.Refresh(); if ($process.MainWindowHandle -ne 0) { break } }
  if ($process.MainWindowHandle -eq 0) { throw 'Editor HWND missing.' }
  Start-Sleep -Seconds 2
  $process.Refresh()
  $window = $process.MainWindowHandle
  $rect = New-Object MoveLoopProbeNative+RECT
  [void][MoveLoopProbeNative]::GetWindowRect($window, [ref]$rect)

  [void][MoveLoopProbeNative]::SendMessage($window, 0x0231, [IntPtr]::Zero, [IntPtr]::Zero)
  [void][MoveLoopProbeNative]::SendMessage($window, 0x0216, [IntPtr]::Zero, [ref]$rect)
  $moveTimes = Measure-Timers $window 30
  [void][MoveLoopProbeNative]::SendMessage($window, 0x0232, [IntPtr]::Zero, [IntPtr]::Zero)

  [void][MoveLoopProbeNative]::SendMessage($window, 0x0231, [IntPtr]::Zero, [IntPtr]::Zero)
  [void][MoveLoopProbeNative]::SendMessage($window, 0x0214, [IntPtr]::new(2), [ref]$rect)
  $sizeTimes = Measure-Timers $window 10
  [void][MoveLoopProbeNative]::SendMessage($window, 0x0232, [IntPtr]::Zero, [IntPtr]::Zero)

  $moveAvg = ($moveTimes | Measure-Object -Average).Average
  $moveMax = ($moveTimes | Measure-Object -Maximum).Maximum
  $sizeAvg = ($sizeTimes | Measure-Object -Average).Average
  "moveTimerAverageMs=$([Math]::Round($moveAvg, 3)) moveTimerMaxMs=$([Math]::Round($moveMax, 3))"
  "resizeTimerAverageMs=$([Math]::Round($sizeAvg, 3))"
  if ($moveAvg -ge $sizeAvg * 0.65) { throw 'Move timers still appear to run the interactive render callback.' }
}
finally {
  Get-Process Boltspark -ErrorAction SilentlyContinue | Stop-Process -Force
}
