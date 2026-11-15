# Focused window-scoped probe for center move, true arc-ball rotation, and
# the clickable WORLD/LOCAL viewport control. No screen-level input injection.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GizmoSpaceNative {
 [DllImport("user32.dll", SetLastError=true)]
 public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
 public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xffff)); }
}
"@

$repo = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $repo 'bin'
$WM_MOUSEMOVE=0x0200; $WM_LBUTTONDOWN=0x0201; $WM_LBUTTONUP=0x0202
$WM_KEYDOWN=0x0100; $WM_KEYUP=0x0101
$script:h=[IntPtr]::Zero

function Send-Mouse([int]$m,[int]$x,[int]$y,[int]$w=0) {
  $r=[IntPtr]::Zero
  [void][GizmoSpaceNative]::SendMessageTimeout($script:h,$m,[IntPtr]$w,[GizmoSpaceNative]::LP($x,$y),0,5000,[ref]$r)
}
function Click([int]$x,[int]$y) {
  Send-Mouse $WM_MOUSEMOVE $x $y; Start-Sleep -Milliseconds 250
  Send-Mouse $WM_LBUTTONDOWN $x $y 1; Start-Sleep -Milliseconds 100
  Send-Mouse $WM_LBUTTONUP $x $y; Start-Sleep -Milliseconds 450
}
function Drag([int]$x,[int]$y,[int]$dx,[int]$dy,[int]$steps=10) {
  Send-Mouse $WM_MOUSEMOVE $x $y; Start-Sleep -Milliseconds 300
  Send-Mouse $WM_LBUTTONDOWN $x $y 1; Start-Sleep -Milliseconds 120
  for($i=1;$i -le $steps;$i++) {
    Send-Mouse $WM_MOUSEMOVE ($x+$dx*$i) ($y+$dy*$i) 1
    Start-Sleep -Milliseconds 45
  }
  Send-Mouse $WM_LBUTTONUP ($x+$dx*$steps) ($y+$dy*$steps)
  Start-Sleep -Milliseconds 500
}
function Key([int]$vk,[int]$scan) {
  $r=[IntPtr]::Zero
  [void][GizmoSpaceNative]::SendMessageTimeout($script:h,$WM_KEYDOWN,[IntPtr]$vk,[IntPtr](1 -bor ($scan -shl 16)),0,5000,[ref]$r)
  Start-Sleep -Milliseconds 100
  [void][GizmoSpaceNative]::SendMessageTimeout($script:h,$WM_KEYUP,[IntPtr]$vk,[IntPtr](0xC0000001 -bor ($scan -shl 16)),0,5000,[ref]$r)
  Start-Sleep -Milliseconds 400
}
function Geometry {
  $rect=New-Object GizmoSpaceNative+RECT
  [void][GizmoSpaceNative]::GetClientRect($script:h,[ref]$rect)
  $left=255.0; $right=386.0; $console=174.0
  $layoutPath=Join-Path $env:LOCALAPPDATA 'Boltspark Engine\layout.json'
  if(Test-Path $layoutPath) {
    $j=Get-Content $layoutPath | ConvertFrom-Json
    $left=[double]$j.leftPanelWidth; $right=[double]$j.rightPanelWidth; $console=[double]$j.consoleHeight
  }
  $vw=$rect.Right-8-$left-$right
  $body=$rect.Bottom-66-20
  $vh=$body-$console-4
  $vx=$left+4; $vy=66
  return @{ cx=[int][Math]::Round($vx+$vw/2); cy=[int][Math]::Round($vy+$vh/2);
    spaceX=[int][Math]::Round($vx+$vw-40); spaceY=86 }
}
function Start-App([string]$log) {
  if(Get-Process hl -ErrorAction SilentlyContinue) { throw 'hl.exe already running' }
  $p=Start-Process (Join-Path $repo 'toolchain\hashlink\hl.exe') -ArgumentList 'boltspark.hl' `
    -WorkingDirectory $bin -RedirectStandardOutput (Join-Path $bin $log) -NoNewWindow -PassThru
  for($i=0;$i -lt 40;$i++) { Start-Sleep -Milliseconds 250; $p.Refresh(); if($p.MainWindowHandle -ne 0){break} }
  if($p.MainWindowHandle -eq 0){throw 'window not found'}
  $script:h=$p.MainWindowHandle; Start-Sleep -Seconds 2
  return $p
}
function Stop-App { & (Join-Path $bin 'close-boltspark.ps1') | Out-Null; Start-Sleep -Milliseconds 300 }

$p=Start-App 'gizmo-center-move-log.txt'; $g=Geometry
Drag $g.cx $g.cy 8 -6 10
Stop-App

$p=Start-App 'gizmo-arcball-log.txt'; $g=Geometry
Key 0x32 0x03
Drag $g.cx $g.cy 8 0 10
Stop-App

$p=Start-App 'gizmo-space-log.txt'; $g=Geometry
Click $g.spaceX $g.spaceY
Click $g.spaceX $g.spaceY
Stop-App

'--- center move ---'
Get-Content (Join-Path $bin 'gizmo-center-move-log.txt') | Select-String '\[gizmo\]|transform space'
'--- center arcball ---'
Get-Content (Join-Path $bin 'gizmo-arcball-log.txt') | Select-String '\[gizmo\]|transform space'
'--- space toggle ---'
Get-Content (Join-Path $bin 'gizmo-space-log.txt') | Select-String 'transform space'
