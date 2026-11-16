param(
    [int]$TimeoutSeconds = 25
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\project-files\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
# Deliberately extensionless: the native picker can return a bare typed name.
$projectFile = Join-Path $workspace 'Demo'
$manifestFile = "$projectFile.boltproject"
$sceneFile = Join-Path (Join-Path $workspace 'Scenes') 'Main Scene.boltscene'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force $workspace | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkProjectFilesApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
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

function Send-Message([IntPtr]$window, [uint32]$message,
        [IntPtr]$wparam, [IntPtr]$lparam) {
    $result = [IntPtr]::Zero
    $sent = [BoltsparkProjectFilesApi]::SendMessageTimeout(
        $window, $message, $wparam, $lparam, 0, 5000, [ref]$result)
    if ($sent -eq [IntPtr]::Zero) {
        throw ('Window message 0x{0:X} failed.' -f $message)
    }
}

function Send-Mouse([IntPtr]$window, [uint32]$message,
        [int]$x, [int]$y, [IntPtr]$buttons) {
    Send-Message $window $message $buttons `
        ([BoltsparkProjectFilesApi]::MakeLParam($x, $y))
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    Send-Mouse $window 0x0200 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 80
    Send-Mouse $window 0x0201 $x $y ([IntPtr]1)
    Send-Mouse $window 0x0202 $x $y ([IntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}

function Send-SaveChord([IntPtr]$window, [int]$virtualKey, [int]$scanCode,
        [bool]$withShift) {
    Send-Message $window 0x0100 ([IntPtr]0x11) ([IntPtr](1 -bor (0x1D -shl 16)))
    if ($withShift) {
        Send-Message $window 0x0100 ([IntPtr]0xA0) ([IntPtr](1 -bor (0x2A -shl 16)))
    }
    Send-Message $window 0x0100 ([IntPtr]$virtualKey) ([IntPtr](1 -bor ($scanCode -shl 16)))
    Send-Message $window 0x0101 ([IntPtr]$virtualKey) ([IntPtr](0xC0000001 -bor ($scanCode -shl 16)))
    if ($withShift) {
        Send-Message $window 0x0101 ([IntPtr]0xA0) ([IntPtr](0xC0000001 -bor (0x2A -shl 16)))
    }
    Send-Message $window 0x0101 ([IntPtr]0x11) ([IntPtr](0xC0000001 -bor (0x1D -shl 16)))
    Start-Sleep -Milliseconds 500
}

function Start-Editor([string]$stdoutPath, [string]$stderrPath) {
    return Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath `
        -NoNewWindow -PassThru
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldSave = $env:BOLTSPARK_PROBE_SAVE_FILE
$oldOpen = $env:BOLTSPARK_PROBE_OPEN_FILE
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$process = $null
$reopen = $null
$fallback = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_SAVE_FILE = $projectFile
    $env:BOLTSPARK_PROBE_OPEN_FILE = $projectFile
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer

    # --- Save Project As from the real File menu -------------------------
    $process = Start-Editor $stdout $stderr
    $window = Wait-Window $process
    [void][BoltsparkProjectFilesApi]::SetWindowPos(
        $window, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    # Add palette -> first primitive, so the saved scene has real content.
    Send-Click $window 47 48
    Send-Click $window 50 115
    Start-Sleep -Milliseconds 300

    # File (60,15) -> Save Project As... (menu row 3, center y=110).
    Send-Click $window 60 15
    Send-Click $window 60 110
    Start-Sleep -Milliseconds 800

    if (-not (Test-Path $manifestFile)) {
        throw 'Save Project As did not append .boltproject to the bare path.'
    }
    if (-not (Test-Path $sceneFile)) { throw 'Save Project As did not write the scene.' }
    $document = Get-Content $sceneFile -Raw | ConvertFrom-Json
    if ($document.entities.Count -lt 2) {
        throw "Saved scene lost the created object: $($document.entities.Count) entities."
    }

    $log = Get-Content $stdout -Raw
    if ($log -notmatch '\[probe\] file dialog save') {
        throw 'Save Project As did not reach the native file-picker call site.'
    }
    if ($log -notmatch '\[console\] project: saved ') {
        throw 'Save Project As did not report a successful save.'
    }
    $titles = [regex]::Matches($log, '\[project\] title=(.*)') |
        ForEach-Object { $_.Groups[1].Value.Trim() }
    if (-not ($titles | Where-Object { $_ -like 'Untitled Project*Main Scene *' })) {
        throw 'Creating an object did not mark the untitled project dirty.'
    }
    $lastTitle = $titles[-1]
    if ($lastTitle -notlike 'Demo*Main Scene' -or $lastTitle.EndsWith(' *')) {
        throw "Save Project As title is wrong: $lastTitle"
    }

    # Ctrl+S saves the current scene; Ctrl+Shift+S saves scene and project.
    Send-SaveChord $window 0x53 0x1F $false
    Send-SaveChord $window 0x53 0x1F $true
    $saveLog = Get-Content $stdout -Raw
    if ($saveLog -notmatch '\[console\] scene: saved ') {
        throw 'Ctrl+S did not save the current scene.'
    }
    if ($saveLog -notmatch '\[console\] saved all: ') {
        throw 'Ctrl+Shift+S did not save all.'
    }

    # Scene creation/opening now belongs to the docked Asset Browser (covered
    # by Test-AssetBrowser.ps1). This probe stays focused on project files.

    # Dirty again with a Scene-menu creation, then verify both close answers.
    # The Scene menu also closes any still-open palette before opening.
    Send-Click $window 150 15
    Send-Click $window 150 44
    Start-Sleep -Milliseconds 300
    $dirtyTitles = [regex]::Matches((Get-Content $stdout -Raw), '\[project\] title=(.*)') |
        ForEach-Object { $_.Groups[1].Value.Trim() }
    if (-not ($dirtyTitles | Where-Object { $_ -like 'Demo*Main Scene *' })) {
        throw 'Creating an object did not mark the title dirty.'
    }
    # Persist the switched-to scene with its new object, then dirty once more
    # so the close prompt has unsaved work to protect.
    Send-Click $window 60 15
    Send-Click $window 60 88    # File -> Save Project
    Start-Sleep -Milliseconds 700
    Send-Click $window 150 15
    Send-Click $window 150 44   # Scene -> Create Empty
    Start-Sleep -Milliseconds 300
    Set-Content -LiteralPath $closeAnswer -Value 'no' -Encoding ascii
    [void][BoltsparkProjectFilesApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 800
    if ($process.HasExited) { throw 'Close with answer=no discarded unsaved work.' }
    if ((Get-Content $stdout -Raw) -notmatch '\[probe\] close prompt answer=no') {
        throw 'Close with unsaved work did not reach the confirmation prompt.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkProjectFilesApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Close with answer=yes did not exit.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "First editor session wrote stderr; inspect $stderr."
    }

    # --- Open Project from the real File menu ----------------------------
    $reopenStdout = Join-Path $outputDir 'reopen-stdout.log'
    $reopenStderr = Join-Path $outputDir 'reopen-stderr.log'
    $reopen = Start-Editor $reopenStdout $reopenStderr
    $reopenWindow = Wait-Window $reopen
    [void][BoltsparkProjectFilesApi]::SetWindowPos(
        $reopenWindow, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    # File -> Open Project... (menu row 1, center y=66).
    Send-Click $reopenWindow 60 15
    Send-Click $reopenWindow 60 66
    Start-Sleep -Milliseconds 800

    $reopenLog = Get-Content $reopenStdout -Raw
    if ($reopenLog -notmatch '\[probe\] file dialog open') {
        throw 'Open Project did not reach the native file-picker call site.'
    }
    if ($reopenLog -notmatch '\[console\] project: opened ') {
        throw 'Open Project did not report a successful open.'
    }
    if ($reopenLog -notmatch '\[project\] title=Demo') {
        throw 'Open Project did not restore the saved project title.'
    }
    if ($reopenLog -notmatch '\[probe\] scene loaded entities=3') {
        throw 'Open Project did not rebuild the saved scene graph.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkProjectFilesApi]::PostMessage(
        $reopenWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $reopen.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Reopened editor did not close.'
    }
    $reopen = $null
    if ((Get-Item $reopenStderr).Length -ne 0) {
        throw "Reopened editor wrote stderr; inspect $reopenStderr."
    }

    # --- Save Scene on an untitled project routes to Save Project As -------
    $fallbackProject = Join-Path $workspace 'Fallback'
    $fallbackManifest = "$fallbackProject.boltproject"
    $env:BOLTSPARK_PROBE_SAVE_FILE = $fallbackProject
    $env:BOLTSPARK_PROBE_OPEN_FILE = 'cancel'
    $fallbackStdout = Join-Path $outputDir 'fallback-stdout.log'
    $fallbackStderr = Join-Path $outputDir 'fallback-stderr.log'
    $fallback = Start-Editor $fallbackStdout $fallbackStderr
    $fallbackWindow = Wait-Window $fallback
    [void][BoltsparkProjectFilesApi]::SetWindowPos(
        $fallbackWindow, [IntPtr]::Zero, 40, 40, 1440, 900, 0x0004)
    Start-Sleep -Seconds 1

    # File -> Save Current Scene (menu row 4, center y=132).
    Send-Click $fallbackWindow 60 15
    Send-Click $fallbackWindow 60 132
    Start-Sleep -Milliseconds 800

    if (-not (Test-Path $fallbackManifest)) {
        throw 'Save Scene on an untitled project did not route to Save Project As.'
    }
    $fallbackLog = Get-Content $fallbackStdout -Raw
    if ($fallbackLog -match 'save scene failed') {
        throw "Save Scene reported a failure on an untitled project: $fallbackLog"
    }
    if ($fallbackLog -notmatch '\[probe\] file dialog save') {
        throw 'Save Scene did not reach the file-picker call site.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Scenes\Main Scene.boltscene'))) {
        throw 'Scene was not saved inside the newly created project folder.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkProjectFilesApi]::PostMessage(
        $fallbackWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $fallback.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Fallback editor did not close.'
    }
    $fallback = $null
    if ((Get-Item $fallbackStderr).Length -ne 0) {
        throw "Fallback editor wrote stderr; inspect $fallbackStderr."
    }

    Write-Host '[project-files] Menu-driven save-as, bare-path handling, dirty marker, close prompt, reopen, and Save Scene fallback passed.' -ForegroundColor Green
    Write-Host "[project-files] Evidence: $outputDir"
}
finally {
    foreach ($running in @($process, $reopen, $fallback)) {
        if ($null -ne $running -and -not $running.HasExited) {
            Stop-Process -Id $running.Id -Force
        }
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_SAVE_FILE = $oldSave
    $env:BOLTSPARK_PROBE_OPEN_FILE = $oldOpen
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
}
