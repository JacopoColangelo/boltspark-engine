param(
    [int]$TimeoutSeconds = 45
)

# End-to-end coverage for the Unity-style material workflow:
#   Add -> Material, Add -> Import Asset, drag the imported texture from the
#   Asset Browser onto the Albedo slot, save, and verify the .boltmaterial JSON.
# This exercises the typed TextureAsset payload and the typed drop target.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\material-texture-drag\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$pickerDir = Join-Path $outputDir 'picker'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
foreach ($path in @($localAppData, $workspace, $pickerDir)) {
    New-Item -ItemType Directory -Force $path | Out-Null
}
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

Add-Type -AssemblyName System.Drawing
$texturePath = Join-Path $pickerDir 'TestAlbedo.png'
$bitmap = New-Object System.Drawing.Bitmap(64, 64)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::FromArgb(255, 200, 80, 40))
$graphics.Dispose()
$bitmap.Save($texturePath, [System.Drawing.Imaging.ImageFormat]::Png)
$bitmap.Dispose()

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TextureDragApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Read-Log { return [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) }
function Send-Mouse([IntPtr]$window, [uint32]$message, [int]$x, [int]$y, [IntPtr]$buttons) {
    $result = [IntPtr]::Zero
    [void][TextureDragApi]::SendMessageTimeout($window, $message, $buttons,
        [TextureDragApi]::LP($x, $y), 0, 5000, [ref]$result)
}
function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Mouse $window 0x0200 $x $y ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 $x $y ([IntPtr]1)
    Send-Mouse $window 0x0202 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}
function Send-Text([IntPtr]$window, [string]$text) {
    $result = [IntPtr]::Zero
    foreach ($character in $text.ToCharArray()) {
        # VK_DELETE (0x2E) collides with '.', so use the OEM period key.
        $vk = if ($character -eq '.') { 0xBE } else { [int]$character }
        [void][TextureDragApi]::SendMessageTimeout($window, 0x0100,
            [IntPtr]$vk, [IntPtr]1, 0, 5000, [ref]$result)
        Start-Sleep -Milliseconds 30
        # Heaps already turns VK_OEM_PERIOD into '.', so no extra WM_CHAR.
        if ($character -ne '.') {
            [void][TextureDragApi]::SendMessageTimeout($window, 0x0102,
                [IntPtr][int]$character, [IntPtr]1, 0, 5000, [ref]$result)
            Start-Sleep -Milliseconds 30
        }
        [void][TextureDragApi]::SendMessageTimeout($window, 0x0101,
            [IntPtr]$vk, [IntPtr]1, 0, 5000, [ref]$result)
        Start-Sleep -Milliseconds 40
    }
}

function Wait-For([string]$pattern, [int]$seconds, [string]$message) {
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        Start-Sleep -Milliseconds 120
        $log = Read-Log
    } while ($log -notmatch $pattern -and [DateTime]::UtcNow -lt $deadline)
    if ($log -notmatch $pattern) { throw "$message. Log tail: $($log.Substring([Math]::Max(0, $log.Length - 800)))" }
    return $log
}

# Probe picker answer: numbered file inside the picker directory itself.
Set-Content -LiteralPath (Join-Path $pickerDir 'pick-1.txt') -Value $texturePath -Encoding ascii

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$oldUntitled = $env:BOLTSPARK_PROBE_UNTITLED_DIR
$oldPicker = $env:BOLTSPARK_PROBE_PICKER_DIR
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $workspace
    $env:BOLTSPARK_PROBE_PICKER_DIR = $pickerDir

    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $window = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 125
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    [void][TextureDragApi]::SetWindowPos($window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Wait-For '\[probe\] asset browser entries=' 15 'Browser never completed its initial scan' | Out-Null

    $client = New-Object TextureDragApi+RECT
    [void][TextureDragApi]::GetClientRect($window, [ref]$client)
    $contentY = ([int]$client.Bottom - 20 - 160) + 24
    $consoleX = 254
    $consoleWidth = [int]$client.Right - 584
    $addX = $consoleX + $consoleWidth - 64 + 27
    $addY = $contentY + 13

    # Add -> Material (row 3) opens a document in the Material Editor.
    Send-Click $window $addX $addY
    Send-Click $window ($addX + 45) ($contentY + 26 + 80)
    Wait-For '\[probe\] material editor opened source=' 12 'Add -> Material did not open the editor' | Out-Null

    # Add -> Import Asset (row 2) pulls in the generated PNG.
    Send-Click $window $addX $addY
    Send-Click $window ($addX + 45) ($contentY + 26 + 58)
    Wait-For 'import completed count=1' 15 'Texture import did not complete' | Out-Null

    # Probe logs the texture slot rect once a compatible drag begins. Start a
    # short drag from each first-row tile until the source is our PNG.
    $tileY = $contentY + 26 + 4 + 40
    $tileXs = @(($consoleX + 118 + 8 + 44), ($consoleX + 118 + 8 + 44 + 118),
        ($consoleX + 118 + 8 + 44 + 236), ($consoleX + 118 + 8 + 44 + 354))
    $sourceX = -1
    foreach ($candidateX in $tileXs) {
        $before = ([regex]::Matches((Read-Log),
            '\[probe\] asset drag begin source=')).Count
        Send-Mouse $window 0x0200 $candidateX $tileY ([IntPtr]::Zero)
        Send-Mouse $window 0x0201 $candidateX $tileY ([IntPtr]1)
        Send-Mouse $window 0x0200 ($candidateX + 14) ($tileY + 14) ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 200
        $after = Read-Log
        $dragStarted = ([regex]::Matches($after, '\[probe\] asset drag begin source=')).Count -gt $before
        $isTexture = $after -match '(?m)^\[probe\] asset drag begin source=.*TestAlbedo\.png'
        if ($dragStarted -and $isTexture) {
            $sourceX = $candidateX
            break
        }
        Send-Mouse $window 0x0202 ($candidateX + 14) ($tileY + 14) ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 100
    }
    if ($sourceX -lt 0) { throw 'Could not start a typed drag from the imported texture tile.' }

    $slotMatch = [regex]::Match((Read-Log),
        '\[probe\] asset slot type=texture rect=(-?\d+),(-?\d+) (\d+)x(\d+)')
    if (-not $slotMatch.Success) { throw 'Texture slot did not highlight during the drag.' }
    $targetX = [int]([int]$slotMatch.Groups[1].Value + [int]$slotMatch.Groups[3].Value * 0.5)
    $targetY = [int]([int]$slotMatch.Groups[2].Value + [int]$slotMatch.Groups[4].Value * 0.5)

    # Continue the captured drag onto the slot and release.
    Send-Mouse $window 0x0200 $targetX $targetY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    Send-Mouse $window 0x0202 $targetX $targetY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 500

    # Prove a body control is clickable (not just the header buttons): scrub
    # the Metallic slider to ~75%. Coordinates derive from the albedo slot:
    # slot x = panel x + 12 + 100, slot y = panel y + 140 (header + name row
    # + section header + first row), slot width = inner width - 100.
    $slotLeft = [int]$slotMatch.Groups[1].Value
    $slotTop = [int]$slotMatch.Groups[2].Value
    $slotWidth = [int]$slotMatch.Groups[3].Value
    $railWidth = $slotWidth - 66
    Send-Mouse $window 0x0200 ($slotLeft + [int]($railWidth * 0.75)) ($slotTop + 74) ([IntPtr]::Zero)
    Send-Mouse $window 0x0201 ($slotLeft + [int]($railWidth * 0.75)) ($slotTop + 74) ([IntPtr]1)
    Send-Mouse $window 0x0202 ($slotLeft + [int]($railWidth * 0.75)) ($slotTop + 74) ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 250

    # Project-authored materials must carry the same typed payload as engine
    # materials: drag the material tile onto the Inspector material slot.
    $materialTileX = -1
    foreach ($candidateX in $tileXs) {
        $before = ([regex]::Matches((Read-Log),
            '\[probe\] asset drag begin source=')).Count
        Send-Mouse $window 0x0200 $candidateX $tileY ([IntPtr]::Zero)
        Send-Mouse $window 0x0201 $candidateX $tileY ([IntPtr]1)
        Send-Mouse $window 0x0200 ($candidateX + 14) ($tileY + 14) ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 200
        $after = Read-Log
        $dragStarted = ([regex]::Matches($after, '\[probe\] asset drag begin source=')).Count -gt $before
        $isMaterial = $after -match '(?m)^\[probe\] asset drag begin source=.*\.boltmaterial'
        if ($dragStarted -and $isMaterial) {
            $materialTileX = $candidateX
            break
        }
        Send-Mouse $window 0x0202 ($candidateX + 14) ($tileY + 14) ([IntPtr]::Zero)
        Start-Sleep -Milliseconds 100
    }
    if ($materialTileX -lt 0) { throw 'Could not start a typed drag from the project material tile.' }
    $matSlot = [regex]::Match((Read-Log),
        '\[probe\] asset slot type=material rect=(-?\d+),(-?\d+) (\d+)x(\d+)')
    if (-not $matSlot.Success) { throw 'Inspector material slot did not highlight.' }
    $matX = [int]([int]$matSlot.Groups[1].Value + [int]$matSlot.Groups[3].Value * 0.5)
    $matY = [int]([int]$matSlot.Groups[2].Value + [int]$matSlot.Groups[4].Value * 0.5)
    Send-Mouse $window 0x0200 $matX $matY ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 150
    Send-Mouse $window 0x0202 $matX $matY ([IntPtr]::Zero)
    Wait-For '\[probe\] inspector asset changed material=' 10 'Project material drop onto the Inspector slot did not assign it' | Out-Null

    # Type an exact value into the Metallic slider's numeric field.
    Send-Click $window ($slotLeft + $slotWidth - 28) ($slotTop + 74)
    # Select the existing text so typing replaces it.
    $keyResult = [IntPtr]::Zero
    [void][TextureDragApi]::SendMessageTimeout($window, 0x0100,
        [IntPtr]0x11, [IntPtr]0x001D0001, 0, 5000, [ref]$keyResult)
    [void][TextureDragApi]::SendMessageTimeout($window, 0x0100,
        [IntPtr]0x41, [IntPtr]0x001E0001, 0, 5000, [ref]$keyResult)
    [void][TextureDragApi]::SendMessageTimeout($window, 0x0101,
        [IntPtr]0x41, [IntPtr]0xC01E0001, 0, 5000, [ref]$keyResult)
    [void][TextureDragApi]::SendMessageTimeout($window, 0x0101,
        [IntPtr]0x11, [IntPtr]0xC01D0001, 0, 5000, [ref]$keyResult)
    Start-Sleep -Milliseconds 80
    Send-Text $window '0'
    $result = [IntPtr]::Zero
    [void][TextureDragApi]::SendMessageTimeout($window, 0x0100,
        [IntPtr]0x0D, [IntPtr]0x001C0001, 0, 5000, [ref]$result)
    [void][TextureDragApi]::SendMessageTimeout($window, 0x0101,
        [IntPtr]0x0D, [IntPtr]0xC01C0001, 0, 5000, [ref]$result)
    # Let the debounced write finish before inspecting the document.
    Start-Sleep -Milliseconds 900

    # No Save button: value edits persist automatically after a short debounce.
    Wait-For '\[probe\] material auto-saved source=' 10 'Material Editor did not auto-save the edited document' | Out-Null

    $documents = @(Get-ChildItem -LiteralPath $workspace -Recurse -Filter '*.boltmaterial')
    if ($documents.Count -lt 1) { throw 'No material document was written.' }
    $saved = Get-Content -LiteralPath $documents[0].FullName -Raw | ConvertFrom-Json
    if (-not $saved.albedoTexture -match 'TestAlbedo\.png') {
        throw "Albedo slot was not assigned by the drop (albedoTexture=$($saved.albedoTexture))."
    }
    if ([double]$saved.metallic -gt 0.01) {
        throw "Typing into the Metallic slider field did not persist (metallic=$($saved.metallic))."
    }
    Write-Host "[material-texture-drag] dropped $($saved.albedoTexture); typed slider value persisted as metallic=$($saved.metallic)."

    Write-Host "[material-texture-drag] Evidence: $outputDir"
} finally {
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $oldUntitled
    $env:BOLTSPARK_PROBE_PICKER_DIR = $oldPicker
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
}
