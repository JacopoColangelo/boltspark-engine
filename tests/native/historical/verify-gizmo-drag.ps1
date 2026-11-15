# Automated evidence probe for the Move-tool transform gizmo (Boltspark editor).
#
# Input safety: this probe never injects screen-level input (no SetCursorPos /
# mouse_event). Every event is addressed directly to the Boltspark window
# handle, so nothing can land in another application.
#
# Delivery: SendMessageTimeout instead of PostMessage. Posted input messages
# only surface while the HashLink window owns the foreground queue, whereas a
# synchronous send reaches the window procedure regardless of focus.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GizmoNative {
 [DllImport("user32.dll", SetLastError = true)]
 public static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
 public static IntPtr Makelparam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@
$WM_MOUSEMOVE   = [uint32]0x0200
$WM_LBUTTONDOWN = [uint32]0x0201
$WM_LBUTTONUP   = [uint32]0x0202

$p = Get-Process -Name hl -ErrorAction Stop | Select-Object -First 1
$h = $p.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw 'Boltspark main window handle not ready.' }
$rect = New-Object GizmoNative+RECT
[void][GizmoNative]::GetClientRect($h, [ref]$rect)
$width = $rect.Right; $height = $rect.Bottom

$lines = [Collections.Generic.List[string]]::new()

function Send([uint32]$msg, [int]$x, [int]$y, [IntPtr]$wparam) {
    $result = [IntPtr]::Zero
    $sent = [GizmoNative]::SendMessageTimeout($h, $msg, $wparam,
        [GizmoNative]::Makelparam($x, $y), 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        $lines.Add(('FAILED SendMessageTimeout msg=0x{0:X} at ({1},{2})' -f $msg, $x, $y))
    }
}

# Reproduce DockLayout.calculate for the saved panel widths so the gizmo
# (which sits at the world origin, centered by the camera) can be located.
$left = 250.0; $right = 318.0; $console = 160.0
$layoutPath = Join-Path $env:LOCALAPPDATA 'Boltspark Engine\layout.json'
if (Test-Path $layoutPath) {
    $layout = Get-Content $layoutPath | ConvertFrom-Json
    if ($layout.version -eq 1) {
        $left = [double]$layout.leftPanelWidth
        $right = [double]$layout.rightPanelWidth
        $console = [double]$layout.consoleHeight
    }
}
$bodyTop = 66; $statusBar = 20; $splitter = 4
$bodyHeight = [Math]::Max(0, $height - $bodyTop - $statusBar)
$panelSpace = [Math]::Max(0, $width - $splitter * 2)
if ($panelSpace -ge 200 + 240 + 260) {
    $viewportWidth = $panelSpace - $left - $right
} else {
    $left = [Math]::Min(200, $panelSpace * 0.3)
    $right = [Math]::Min(260, $panelSpace * 0.35)
    $viewportWidth = $panelSpace - $left - $right
}
if ($bodyHeight -ge 168 + $splitter + 96) {
    $console = [Math]::Max(140, [Math]::Min($console, $bodyHeight - 168 - $splitter))
    $viewportHeight = $bodyHeight - $console - $splitter
} else {
    $viewportHeight = [Math]::Max(0, $bodyHeight * 0.6 - $splitter)
}
$centerX = [int]([Math]::Round($left + $splitter + $viewportWidth * 0.5))
$centerY = [int]([Math]::Round($bodyTop + $viewportHeight * 0.5))

$lines.Add("Client=${width}x${height} layout(left=$left right=$right console=$console)")
$lines.Add("ViewportCenter=($centerX,$centerY) send=SendMessageTimeout")

# Drag 1: hover the gizmo origin (the pointer ray meets the X axis segment at
# its base), press, drag right/up, release. The cube should move along +X only.
Send $WM_MOUSEMOVE $centerX $centerY ([IntPtr]::Zero)
Start-Sleep -Milliseconds 350
$lines.Add("hover: WM_MOUSEMOVE at ($centerX,$centerY)")

Send $WM_LBUTTONDOWN $centerX $centerY ([IntPtr]1)
Start-Sleep -Milliseconds 150
for ($step = 1; $step -le 12; $step++) {
    Send $WM_MOUSEMOVE ($centerX + $step * 12) ($centerY - $step * 3) ([IntPtr]1)
    Start-Sleep -Milliseconds 40
}
Start-Sleep -Milliseconds 200
Send $WM_LBUTTONUP ($centerX + 144) ($centerY - 36) ([IntPtr]::Zero)
Start-Sleep -Milliseconds 500
$lines.Add('drag 1: press center, 12 WM_MOUSEMOVE steps of (+12,-3) px, release at (+144,-36)')

# Drag 2: the cube now sits at (-1.93, 0, 0), which projects to engine pixel
# (790.5, 329.9) for this camera (validated: Heaps' handedness projects the +X
# arrow left-down, so a right-up pointer drag moves the foot toward -X).
# Press on the cube's pixel - the pointer ray meets the X segment exactly at
# axisT ~ 0 - then drag back to the viewport center (where the world origin
# projects), which should return the cube to x = 0.
$gizmoX = $centerX + 136
$gizmoY = $centerY - 54
Send $WM_MOUSEMOVE $gizmoX $gizmoY ([IntPtr]::Zero)
Start-Sleep -Milliseconds 350
Send $WM_LBUTTONDOWN $gizmoX $gizmoY ([IntPtr]1)
Start-Sleep -Milliseconds 150
for ($step = 1; $step -le 12; $step++) {
    $sx = [int]([Math]::Round($gizmoX + ($centerX - $gizmoX) * $step / 12))
    $sy = [int]([Math]::Round($gizmoY + ($centerY - $gizmoY) * $step / 12))
    Send $WM_MOUSEMOVE $sx $sy ([IntPtr]1)
    Start-Sleep -Milliseconds 40
}
Start-Sleep -Milliseconds 200
Send $WM_LBUTTONUP $centerX $centerY ([IntPtr]::Zero)
Start-Sleep -Milliseconds 500
$lines.Add('drag 2: press on the cube pixel (+136,-54), 12 WM_MOUSEMOVE steps back to the viewport center, release')
$lines.Add('expected: drag 1 moves sampleCube position.x 0 -> -1.93 (axis-locked), drag 2 returns it to 0')

$lines | Set-Content -LiteralPath 'bin\gizmo-drag-evidence.txt' -Encoding UTF8
$lines
