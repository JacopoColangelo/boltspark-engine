param(
    [int]$SettleSeconds = 5,
    [int]$TimeoutSeconds = 30,
    [switch]$MaterialEditor,
    [switch]$ContextMenu
)

# Visual probe for the deferred PBR viewport: launches the editor, captures a
# PrintWindow screenshot after the deferred pipeline has compiled its shaders,
# then closes cleanly. Any shader/pipeline failure is written to stderr.log.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$outputDir = Join-Path $repoRoot 'bin\test-results\pbr-viewport-probe'
$localAppData = Join-Path $outputDir 'localappdata'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$screenshot = Join-Path $outputDir 'viewport.png'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
# Always start from a clean editor profile so a previously docked Material
# Editor cannot skew the geometry under test.
if (Test-Path $outputDir) { Remove-Item -LiteralPath $outputDir -Recurse -Force }
New-Item -ItemType Directory -Force $localAppData | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PbrProbeApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
}
"@
Add-Type -AssemblyName System.Drawing

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru

    $window = [IntPtr]::Zero
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early with code $($process.ExitCode)." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    [void][PbrProbeApi]::SetWindowPos($window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds $SettleSeconds

    $rect = New-Object PbrProbeApi+RECT
    if (-not [PbrProbeApi]::GetWindowRect($window, [ref]$rect)) { throw 'GetWindowRect failed.' }
    $width = [int]$rect.Right - [int]$rect.Left
    $height = [int]$rect.Bottom - [int]$rect.Top
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    if (-not [PbrProbeApi]::PrintWindow($window, $hdc, 2)) {
        $graphics.ReleaseHdc($hdc)
        throw 'PrintWindow failed.'
    }
    $graphics.ReleaseHdc($hdc)
    $bitmap.Save($screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()

    if ($ContextMenu) {
        function Send-ClientMouse([IntPtr]$window, [uint32]$message,
                [int]$x, [int]$y, [IntPtr]$buttons) {
            $ignored = [IntPtr]::Zero
            [void][PbrProbeApi]::SendMessageTimeout($window, $message, $buttons,
                [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF)), 0, 5000, [ref]$ignored)
        }
        # Empty area of the Asset Browser grid, then hover the "New..." row.
        $menuX = 1050
        $menuY = 770
        Send-ClientMouse $window 0x0204 $menuX $menuY ([IntPtr]2) # right down
        Send-ClientMouse $window 0x0205 $menuX $menuY ([IntPtr]2) # right up
        Start-Sleep -Milliseconds 300
        Send-ClientMouse $window 0x0200 ($menuX + 30) ($menuY + 14) ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 300
        $menuShot = Join-Path $outputDir 'context-menu.png'
        $bitmap = New-Object System.Drawing.Bitmap($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $hdc = $graphics.GetHdc()
        [void][PbrProbeApi]::PrintWindow($window, $hdc, 2)
        $graphics.ReleaseHdc($hdc)
        $bitmap.Save($menuShot, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        Write-Host "[pbr-probe] context menu screenshot: $menuShot"
    }

    if ($MaterialEditor) {
        function Send-ClientClick([IntPtr]$window, [int]$x, [int]$y) {
            $point = [IntPtr](($y -shl 16) -bor ($x -band 0xFFFF))
            $ignored = [IntPtr]::Zero
            [void][PbrProbeApi]::SendMessageTimeout($window, 0x0200, [IntPtr]::Zero, $point, 0, 5000, [ref]$ignored)
            [void][PbrProbeApi]::SendMessageTimeout($window, 0x0201, [IntPtr]1, $point, 0, 5000, [ref]$ignored)
            [void][PbrProbeApi]::SendMessageTimeout($window, 0x0202, [IntPtr]::Zero, $point, 0, 5000, [ref]$ignored)
            Start-Sleep -Milliseconds 200
        }
        $client = New-Object PbrProbeApi+RECT
        [void][PbrProbeApi]::GetClientRect($window, [ref]$client)
        $contentY = ([int]$client.Bottom - 20 - 160) + 24
        $addX = 254 + ([int]$client.Right - 584) - 64 + 27
        $addY = $contentY + 13
        # Add -> Material (fourth menu row).
        Send-ClientClick $window $addX $addY
        Send-ClientClick $window ($addX + 45) ($contentY + 26 + 80)
        Start-Sleep -Milliseconds 900
        # Single-click the new material tile: its highlight must appear now.
        Send-ClientClick $window (254 + 118 + 8 + 44 + 118) ($contentY + 26 + 4 + 40)
        Start-Sleep -Milliseconds 200

        # Expand the last section so the content exceeds the panel height.
        Send-ClientClick $window ([int]$client.Right - 140) ([int]$client.Bottom - 82)
        Start-Sleep -Milliseconds 250

        # Wheel over the Material Editor body exercises the scroll catcher.
        $scrollBodyX = [int]$client.Right - 140
        $scrollBodyY = 400
        $ignored = [IntPtr]::Zero
        $wheelParam = [IntPtr]([int](-120 -shl 16))
        $wheelPoint = [IntPtr](($scrollBodyY -shl 16) -bor ($scrollBodyX -band 0xFFFF))
        for ($step = 0; $step -lt 3; $step++) {
            [void][PbrProbeApi]::SendMessageTimeout($window, 0x020A, $wheelParam,
                $wheelPoint, 0, 5000, [ref]$ignored)
            Start-Sleep -Milliseconds 120
        }
        Start-Sleep -Milliseconds 300
        $scrollLog = [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
        if ($scrollLog -notmatch '\[probe\] material scroll y=') {
            throw 'Wheel over the Material Editor did not reach its scroll handler.'
        }

        $editorShot = Join-Path $outputDir 'material-editor.png'
        $bitmap = New-Object System.Drawing.Bitmap($width, $height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $hdc = $graphics.GetHdc()
        [void][PbrProbeApi]::PrintWindow($window, $hdc, 2)
        $graphics.ReleaseHdc($hdc)
        $bitmap.Save($editorShot, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        Write-Host "[pbr-probe] material editor screenshot: $editorShot"
    }

    $result = [IntPtr]::Zero
    [void][PbrProbeApi]::SendMessageTimeout($window, 0x0010, [IntPtr]::Zero,
        [IntPtr]::Zero, 0, 5000, [ref]$result)
    if (-not $process.WaitForExit(8000)) { throw 'Editor did not close after WM_CLOSE.' }
    $errors = [string](Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
    if ($errors -match 'ERROR|error|Can.t cast|Error') {
        throw "Runtime errors detected:`n$errors"
    }
    Write-Host "[pbr-probe] screenshot: $screenshot"
    Write-Host '[pbr-probe] deferred viewport launch, render, and close passed.'
} finally {
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    if ($process -ne $null -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
