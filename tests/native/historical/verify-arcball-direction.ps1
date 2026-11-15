# Focused, window-scoped regression for off-center arcball handedness.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ArcballDirectionNative {
 [DllImport("user32.dll", SetLastError=true)]
 public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
 public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xffff)); }
}
"@

$repo = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $repo 'bin'
$stdout = Join-Path $bin 'arcball-direction-runtime.txt'
$stderr = Join-Path $bin 'arcball-direction-runtime.stderr.txt'
$WM_MOUSEMOVE=0x0200; $WM_LBUTTONDOWN=0x0201; $WM_LBUTTONUP=0x0202
$WM_KEYDOWN=0x0100; $WM_KEYUP=0x0101

if (Get-Process hl -ErrorAction SilentlyContinue) {
  throw 'hl.exe already running'
}
$env:BOLTSPARK_PROBE = '1'
$p = Start-Process (Join-Path $repo 'toolchain\hashlink\hl.exe') -ArgumentList 'boltspark.hl' `
  -WorkingDirectory $bin -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
  -NoNewWindow -PassThru
for($i=0;$i -lt 40;$i++) {
  Start-Sleep -Milliseconds 250
  $p.Refresh()
  if($p.MainWindowHandle -ne 0){break}
}
if($p.MainWindowHandle -eq 0){throw 'window not found'}
$h=$p.MainWindowHandle
Start-Sleep -Seconds 2

function Send-Mouse([int]$m,[int]$x,[int]$y,[int]$w=0) {
  $r=[IntPtr]::Zero
  [void][ArcballDirectionNative]::SendMessageTimeout($h,$m,[IntPtr]$w,[ArcballDirectionNative]::LP($x,$y),0,5000,[ref]$r)
}
function Send-Key([int]$vk,[int]$scan) {
  $r=[IntPtr]::Zero
  [void][ArcballDirectionNative]::SendMessageTimeout($h,$WM_KEYDOWN,[IntPtr]$vk,[IntPtr](1 -bor ($scan -shl 16)),0,5000,[ref]$r)
  Start-Sleep -Milliseconds 100
  [void][ArcballDirectionNative]::SendMessageTimeout($h,$WM_KEYUP,[IntPtr]$vk,[IntPtr](0xC0000001 -bor ($scan -shl 16)),0,5000,[ref]$r)
  Start-Sleep -Milliseconds 400
}

$rect=New-Object ArcballDirectionNative+RECT
[void][ArcballDirectionNative]::GetClientRect($h,[ref]$rect)
$left=255.0; $right=386.0; $console=174.0
$layoutPath=Join-Path $env:LOCALAPPDATA 'Boltspark Engine\layout.json'
if(Test-Path $layoutPath) {
  $j=Get-Content $layoutPath | ConvertFrom-Json
  $left=[double]$j.leftPanelWidth; $right=[double]$j.rightPanelWidth; $console=[double]$j.consoleHeight
}
$vw=$rect.Right-8-$left-$right
$body=$rect.Bottom-66-20
$vh=$body-$console-4
$cx=[int][Math]::Round($left+4+$vw/2)
$cy=[int][Math]::Round(66+$vh/2)

# E selects Rotate. Begin halfway from center to the rim, then drag upward:
# this has a strong tangential/view-axis component and exposed the old sign flip.
Send-Key 0x45 0x12
$x=$cx+40; $y=$cy
Send-Mouse $WM_MOUSEMOVE $x $y
Start-Sleep -Milliseconds 250
Send-Mouse $WM_LBUTTONDOWN $x $y 1
Start-Sleep -Milliseconds 120
for($i=1;$i -le 12;$i++) {
  Send-Mouse $WM_MOUSEMOVE $x ($y-3*$i) 1
  Start-Sleep -Milliseconds 35
}
Send-Mouse $WM_LBUTTONUP $x ($y-36)
Start-Sleep -Milliseconds 500

& (Join-Path $bin 'close-boltspark.ps1') | Out-Null
Start-Sleep -Milliseconds 300
Get-Content $stdout | Select-String '\[gizmo\]'
if ((Get-Item $stderr).Length -ne 0) {
  throw "Runtime stderr was not empty: $stderr"
}
