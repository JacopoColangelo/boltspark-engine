$ErrorActionPreference = 'Stop'
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FirstOpenNative {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder text, int length);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint command);
  public static IntPtr Point(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@
function Find-VisibleWindow([int]$processId, [string]$titlePrefix) {
  $script:matchedWindow = [IntPtr]::Zero
  $callback = [FirstOpenNative+EnumProc]{ param($window, $unused)
    $windowPid = [uint32]0
    [void][FirstOpenNative]::GetWindowThreadProcessId($window, [ref]$windowPid)
    if ($windowPid -eq $processId -and [FirstOpenNative]::IsWindowVisible($window)) {
      $title = [Text.StringBuilder]::new(256)
      [void][FirstOpenNative]::GetWindowText($window, $title, $title.Capacity)
      if ($title.ToString().StartsWith($titlePrefix)) { $script:matchedWindow = $window; return $false }
    }
    return $true
  }
  [void][FirstOpenNative]::EnumWindows($callback, [IntPtr]::Zero)
  return $script:matchedWindow
}
function Send-Move([IntPtr]$window, [int]$x, [int]$y) {
  [void][FirstOpenNative]::PostMessage($window, 0x0200, [IntPtr]::Zero, [FirstOpenNative]::Point($x, $y))
}
function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
  Send-Move $window $x $y
  [void][FirstOpenNative]::PostMessage($window, 0x0201, [IntPtr]::new(1), [FirstOpenNative]::Point($x, $y))
  [void][FirstOpenNative]::PostMessage($window, 0x0202, [IntPtr]::Zero, [FirstOpenNative]::Point($x, $y))
}
Get-Process Boltspark -ErrorAction SilentlyContinue | Stop-Process -Force
$repo = Split-Path -Parent $PSScriptRoot
$release = Join-Path $repo 'release'
$main = Start-Process (Join-Path $release 'Boltspark.exe') -WorkingDirectory $release -PassThru
try {
  $editor = [IntPtr]::Zero
  for ($i = 0; $i -lt 100; $i++) { Start-Sleep -Milliseconds 100; $editor = Find-VisibleWindow $main.Id 'Boltspark Engine'; if ($editor -ne [IntPtr]::Zero) { break } }
  if ($editor -eq [IntPtr]::Zero) { throw 'Editor HWND missing.' }
  Start-Sleep -Seconds 2
  Send-Click $editor 60 15
  Start-Sleep -Milliseconds 400
  Send-Click $editor 110 46
  Start-Sleep -Milliseconds 400
  Send-Click $editor 280 46

  $childProcess = $null
  $keybindings = [IntPtr]::Zero
  for ($i = 0; $i -lt 150; $i++) {
    Start-Sleep -Milliseconds 100
    foreach ($candidate in (Get-Process Boltspark -ErrorAction SilentlyContinue | Where-Object Id -ne $main.Id)) {
      $candidateWindow = Find-VisibleWindow $candidate.Id 'Editor Keybindings'
      if ($candidateWindow -ne [IntPtr]::Zero) { $childProcess = $candidate; $keybindings = $candidateWindow; break }
    }
    if ($keybindings -ne [IntPtr]::Zero) { break }
  }
  if ($keybindings -eq [IntPtr]::Zero) { throw 'First menu open did not show the keybindings HWND.' }
  $owner = [FirstOpenNative]::GetWindow($keybindings, 4)
  "editorPid=$($main.Id) editor=0x$($editor.ToInt64().ToString('X'))"
  "keybindingsPid=$($childProcess.Id) keybindings=0x$($keybindings.ToInt64().ToString('X')) owner=0x$($owner.ToInt64().ToString('X'))"
  "ownerMatches=$($owner -eq $editor)"
  if ($owner -ne $editor) { throw 'First-open keybindings HWND is not owned by the editor.' }
}
finally {
  Get-Process Boltspark -ErrorAction SilentlyContinue | Stop-Process -Force
}
