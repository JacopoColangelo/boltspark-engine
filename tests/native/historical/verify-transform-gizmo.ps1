# Automated evidence probe for the full transform gizmo suite (Boltspark editor).
#
# Covers: Move axis + two-axis plane drags, Rotate axis ring + omni trackball,
# Scale axis + uniform, and the 1/2/3 keyboard tool shortcuts.
#
# Input safety: this probe never injects screen-level input (no SetCursorPos /
# mouse_event). Every mouse and key message is addressed directly to the
# Boltspark window handle via SendMessageTimeout, so nothing can land in
# another application.
#
# Sessions are relaunched between tools so every press starts with the sample
# cube at the world origin (the camera centers the origin in the viewport,
# which makes every press pixel a fixed offset from the viewport center).
#
# Validated projection offsets (engine px, 1440x900 client, fovX 70, camera
# 5.8/4.2/6.4 -> origin), per 1.05 world units from the origin:
#   +X -> (-89, +35)   +Y -> (0, -106)   +Z -> (+81, +39)
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
$WM_KEYDOWN     = [uint32]0x0100
$WM_KEYUP       = [uint32]0x0101

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo
$binDir = Join-Path $repo 'bin'

$lines = [Collections.Generic.List[string]]::new()
$lines.Add('transform gizmo probe — SendMessageTimeout to window handle only')

# ---------------------------------------------------------------------------
# Geometry helpers (reproduce DockLayout.calculate for the saved panel widths)
# ---------------------------------------------------------------------------
function Get-ViewportCenter {
    param([IntPtr]$window, [ref]$scale)
    $rect = New-Object GizmoNative+RECT
    [void][GizmoNative]::GetClientRect($window, [ref]$rect)
    $width = $rect.Right; $height = $rect.Bottom
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
    $scale.Value = $width / 1440.0
    return @{
        x = [int]([Math]::Round($left + $splitter + $viewportWidth * 0.5))
        y = [int]([Math]::Round($bodyTop + $viewportHeight * 0.5))
        width = $width; height = $height
    }
}

# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------
function Start-Session([string]$logName) {
    $existing = Get-Process -Name hl -ErrorAction SilentlyContinue
    if ($existing) { throw 'A Boltspark (hl.exe) instance is already running; close it first.' }
    # Synthetic WM_MOUSEMOVE input cannot drive relative (hidden-cursor)
    # mouse mode, so probes run the editor with gizmo drags kept in
    # Absolute mode.
    $env:BOLTSPARK_PROBE = '1'
    $logPath = Join-Path $binDir $logName
    $proc = Start-Process -FilePath (Join-Path $repo 'toolchain\hashlink\hl.exe') `
        -ArgumentList 'boltspark.hl' -WorkingDirectory $binDir `
        -RedirectStandardOutput $logPath -NoNewWindow -PassThru
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 500
        $proc.Refresh()
        if ($proc.HasExited) { throw 'Boltspark exited during launch.' }
        if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    if ($proc.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Boltspark window handle never appeared.' }
    Start-Sleep -Milliseconds 2500   # layout restore + first frames
    return $proc
}

function Stop-Session($proc) {
    & (Join-Path $binDir 'close-boltspark.ps1') | Out-Null
    Start-Sleep -Milliseconds 300
}

# ---------------------------------------------------------------------------
# Input helpers
# ---------------------------------------------------------------------------
$script:windowHandle = [IntPtr]::Zero

function Send([uint32]$msg, [int]$x, [int]$y, [IntPtr]$wparam) {
    $result = [IntPtr]::Zero
    $sent = [GizmoNative]::SendMessageTimeout($script:windowHandle, $msg, $wparam,
        [GizmoNative]::Makelparam($x, $y), 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        $lines.Add(('FAILED SendMessageTimeout msg=0x{0:X} at ({1},{2})' -f $msg, $x, $y))
    }
}

# Number-row key press through the window procedure (scancode in bits 16-23,
# transition flags in bits 30-31 for the up message).
function Send-Key([int]$vk, [int]$scancode) {
    $downL = [IntPtr][int64](1 -bor ($scancode -shl 16))
    $upL = [IntPtr][int64](0xC0000001 -bor ($scancode -shl 16))
    $result = [IntPtr]::Zero
    [void][GizmoNative]::SendMessageTimeout($script:windowHandle, $WM_KEYDOWN,
        [IntPtr]$vk, $downL, 0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 120
    [void][GizmoNative]::SendMessageTimeout($script:windowHandle, $WM_KEYUP,
        [IntPtr]$vk, $upL, 0, 5000, [ref]$result)
    Start-Sleep -Milliseconds 500
}

# Press at (dx,dy) relative to the viewport center, drag in `steps` steps of
# (sx,sy) engine px, release.
function Drag-Handle([string]$label, [int]$dx, [int]$dy, [int]$sx, [int]$sy, [int]$steps) {
    $c = $script:center
    $s = $script:scale
    $px = [int]([Math]::Round($c.x + $dx * $s))
    $py = [int]([Math]::Round($c.y + $dy * $s))
    $ssx = [int]([Math]::Round($sx * $s))
    $ssy = [int]([Math]::Round($sy * $s))
    Send $WM_MOUSEMOVE $px $py ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 350
    Send $WM_LBUTTONDOWN $px $py ([IntPtr]1)
    Start-Sleep -Milliseconds 150
    for ($step = 1; $step -le $steps; $step++) {
        Send $WM_MOUSEMOVE ($px + $ssx * $step) ($py + $ssy * $step) ([IntPtr]1)
        Start-Sleep -Milliseconds 40
    }
    Start-Sleep -Milliseconds 200
    Send $WM_LBUTTONUP ($px + $ssx * $steps) ($py + $ssy * $steps) ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 500
    $lines.Add("drag: $label press rel-center=($dx,$dy) steps=$steps of ($sx,$sy) px")
}

# ---------------------------------------------------------------------------
# Session 1 — Move tool: axis drag out, axis drag back, two-axis plane drag
# ---------------------------------------------------------------------------
$lines.Add('--- session 1: Move tool (axis drags + plane.xy drag) ---')
$proc = Start-Session 'gizmo-runlog-move.txt'
$script:windowHandle = $proc.MainWindowHandle
$scaleRef = 1.0
$script:center = Get-ViewportCenter $script:windowHandle ([ref]$scaleRef)
$script:scale = $scaleRef
$lines.Add(("client={0}x{1} viewportCenter=({2},{3}) scale={4}" -f `
    $center.width, $center.height, $center.x, $center.y, $script:scale))

# Drag 1: press the X shaft at world t=0.3 (pixel -25,+10), drag the pointer to
# the X tip pixel (-89,+35) where the ray meets the axis at t=1.05.
# Expected: position.x 0 -> 1.05-0.3 = 0.75, y/z stay 0 (axis-locked).
Drag-Handle 'move axis.x out' (-25) 10 (-8) 3 8
$lines.Add('expected: sampleCube position.x 0 -> ~0.75 (axis-locked, y=z=0)')

# Drag 2: the cube now sits at (~0.75,0,0); its shaft t=0.3 point is world
# (1.05,0,0) = the X tip pixel (-89,+35). Release at world t=0.3 pixel (-25,+10)
# -> the pointer returns to the same ray family, so x lands back on 0 exactly.
Drag-Handle 'move axis.x back' (-89) 35 8 (-3) 8
$lines.Add('expected: sampleCube position.x returns to 0')

# Plane drag: press the plane.xy handle (world (0.6,0.6,0) -> pixel -49,-39),
# drag the pointer straight up. The drag is constrained to the XY plane, so
# z must stay 0 while x/y follow the pointer (~(-0.31,+0.95) world for 96px).
Drag-Handle 'move plane.xy up' (-49) (-39) 0 (-8) 12
$lines.Add('expected: z stays 0; position ~(x -0.3, y +0.95); two-axis unlocked move')

Stop-Session $proc

# ---------------------------------------------------------------------------
# Session 2 — Rotate tool via the "2" shortcut: axis ring + omni trackball
# ---------------------------------------------------------------------------
$lines.Add('--- session 2: Rotate tool (shortcut 2, axis ring + omni ball) ---')
$proc = Start-Session 'gizmo-runlog-rotate.txt'
$script:windowHandle = $proc.MainWindowHandle
$script:center = Get-ViewportCenter $script:windowHandle ([ref]$scaleRef)
$lines.Add('shortcut: pressing 2 (VK 0x32, scancode 0x03) switches to the Rotate tool')
Send-Key 0x32 0x03
$lines.Add('expected console: "viewport tool: Rotate gizmo active"')

# Axis ring drag: press the radius-0.8 ring through its +Y pixel (0,-81) —
# both the X and Z rings pass through that world-space point — and sweep toward
# +Z. The static default object should rotate around world X only.
Drag-Handle 'rotate axis.x ring sweep' 0 (-81) 7 12 12
$lines.Add('expected: world-X ring changes rotation.x while y/z stay near zero')

# Omni trackball: press the center wire sphere and drag horizontally; the
# virtual-hemisphere axis maps through the camera basis, tumbling the object.
# (The old large outer neutral ring was intentionally removed.)
Drag-Handle 'rotate omni trackball right' 0 0 8 0 12
$lines.Add('expected: euler changes again (omni arc-ball rotation)')

Stop-Session $proc

# ---------------------------------------------------------------------------
# Session 3 — Scale tool via the "3" shortcut: axis scale + uniform, then "1"
# ---------------------------------------------------------------------------
$lines.Add('--- session 3: Scale tool (shortcut 3, axis + uniform), then 1 ---')
$proc = Start-Session 'gizmo-runlog-scale.txt'
$script:windowHandle = $proc.MainWindowHandle
$script:center = Get-ViewportCenter $script:windowHandle ([ref]$scaleRef)
$lines.Add('shortcut: pressing 3 (VK 0x33) switches to the Scale tool')
Send-Key 0x33 0x04
$lines.Add('expected console: "viewport tool: Scale gizmo active"')

# Axis scale: press the X box handle (world (1.05,0,0) -> pixel -89,+35) and
# drag further out along the axis; scale.x grows while y/z stay 1.
Drag-Handle 'scale axis.x outward' (-89) 35 (-8) 3 12
$lines.Add('expected: scale.x ~2 (ratio of axisT), scale.y = scale.z = 1')

# Uniform scale: press the center box (press pixel (-8,-4) resolves to the
# center handle first) and drag away; all three scale values grow together.
Drag-Handle 'scale uniform outward' (-8) (-4) (-8) (-4) 12
$lines.Add('expected: scale.x = scale.y = scale.z ~13 (uniform)')

$lines.Add('shortcut: pressing 1 (VK 0x31) switches back to the Move tool')
Send-Key 0x31 0x02
$lines.Add('expected console: "viewport tool: Move gizmo active"')

Stop-Session $proc

$lines | Set-Content -LiteralPath (Join-Path $binDir 'transform-gizmo-evidence.txt') -Encoding UTF8
$lines
