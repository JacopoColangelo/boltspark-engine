param(
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtime = Join-Path $repoRoot 'toolchain\hashlink\hl.exe'
$bytecode = Join-Path $repoRoot 'bin\boltspark.hl'
$runId = [Guid]::NewGuid().ToString('N')
$outputDir = Join-Path $repoRoot "bin\test-results\import-meshes\$runId"
$localAppData = Join-Path $outputDir 'localappdata'
$workspace = Join-Path $outputDir 'workspace'
$sourceDir = Join-Path $outputDir 'external'
$pickerDir = Join-Path $outputDir 'picker'
$stdout = Join-Path $outputDir 'stdout.log'
$stderr = Join-Path $outputDir 'stderr.log'
$closeAnswer = Join-Path $outputDir 'close-answer.txt'
New-Item -ItemType Directory -Force $localAppData | Out-Null
New-Item -ItemType Directory -Force $workspace | Out-Null
New-Item -ItemType Directory -Force $sourceDir | Out-Null
New-Item -ItemType Directory -Force $pickerDir | Out-Null
Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii

$sourceObj = Join-Path $sourceDir 'Probe Mesh.obj'
Set-Content -LiteralPath $sourceObj -Value "o ProbeMesh`nv 0 0 0`nv 1 0 0`nv 0 1 0`nf 1 2 3`n" -Encoding ascii

# Tiny glTF with an embedded base64 buffer: 3 VEC3 positions + 3 indices.
$bytes = New-Object byte[] 18
$values = @(0,0,0, 1,0,0, 0,1,0)
for ($i = 0; $i -lt $values.Length; $i++) {
    $bytes[$i * 2] = [byte]($values[$i] -band 0xFF)
    $bytes[$i * 2 + 1] = [byte](($values[$i] -shr 8) -band 0xFF)
}
for ($i = 0; $i -lt 3; $i++) {
    $bytes[12 + $i * 2] = [byte]$i
    $bytes[12 + $i * 2 + 1] = 0
}
$base64 = [Convert]::ToBase64String($bytes)
$gltfJson = '{"asset":{"version":"2.0"},' +
    '"buffers":[{"byteLength":18,"uri":"data:application/octet-stream;base64,' + $base64 + '"}],' +
    '"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":12},{"buffer":0,"byteOffset":12,"byteLength":6}],' +
    '"accessors":[{"bufferView":0,"componentType":5123,"count":3,"type":"VEC3"},{"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],' +
    '"meshes":[{"name":"ProbeGltf","primitives":[{"attributes":{"POSITION":0},"indices":1,"mode":4}]}]}'
$sourceGltf = Join-Path $sourceDir 'Probe Mesh.gltf'
[System.IO.File]::WriteAllText($sourceGltf, $gltfJson, (New-Object System.Text.UTF8Encoding($false)))

if (-not (Test-Path $runtime) -or -not (Test-Path $bytecode)) {
    throw 'Development runtime/build missing. Run tools\build.ps1 first.'
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BoltsparkMeshImportApi {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    public static IntPtr LP(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }
}
"@

function Read-Log {
    return [string](Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
}

function Send-Click([IntPtr]$window, [int]$x, [int]$y) {
    $r = [IntPtr]::Zero
    [void][BoltsparkMeshImportApi]::SendMessageTimeout(
        $window, 0x0200, [IntPtr]::Zero, [BoltsparkMeshImportApi]::LP($x, $y), 0, 5000, [ref]$r)
    [void][BoltsparkMeshImportApi]::SendMessageTimeout(
        $window, 0x0201, [IntPtr]1, [BoltsparkMeshImportApi]::LP($x, $y), 0, 5000, [ref]$r)
    [void][BoltsparkMeshImportApi]::SendMessageTimeout(
        $window, 0x0202, [IntPtr]::Zero, [BoltsparkMeshImportApi]::LP($x, $y), 0, 5000, [ref]$r)
    Start-Sleep -Milliseconds 180
}

function Send-Pick([int]$index, [string[]]$paths) {
    $answer = Join-Path $pickerDir "pick-$index.txt"
    Set-Content -LiteralPath $answer -Value ($paths -join '|') -Encoding ascii
}

function Wait-For([string]$pattern, [int]$seconds, [string]$message) {
    $deadline = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        Start-Sleep -Milliseconds 120
        $log = Read-Log
    } while ($log -notmatch $pattern -and [DateTime]::UtcNow -lt $deadline)
    if ($log -notmatch $pattern) { throw "$message. Log: $log" }
    return $log
}

$oldProbe = $env:BOLTSPARK_PROBE
$oldLocalAppData = $env:LOCALAPPDATA
$oldAnswer = $env:BOLTSPARK_PROBE_CLOSE_ANSWER
$oldUntitled = $env:BOLTSPARK_PROBE_UNTITLED_DIR
$oldPickerDir = $env:BOLTSPARK_PROBE_PICKER_DIR
$process = $null
try {
    $env:BOLTSPARK_PROBE = '1'
    $env:LOCALAPPDATA = $localAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $closeAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $workspace
    $env:BOLTSPARK_PROBE_PICKER_DIR = $pickerDir
    Send-Pick 1 @($sourceObj)

    $process = Start-Process $runtime -ArgumentList 'boltspark.hl' `
        -WorkingDirectory (Join-Path $repoRoot 'bin') `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -NoNewWindow -PassThru

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $window = [IntPtr]::Zero
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 130
        $process.Refresh()
        if ($process.HasExited) { throw "Editor exited early (code $($process.ExitCode))." }
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $window = $process.MainWindowHandle
            break
        }
    }
    if ($window -eq [IntPtr]::Zero) { throw 'Editor HWND did not appear.' }
    Wait-For '\[probe\] asset browser entries=' 12 'Browser never completed its initial scan' | Out-Null

    $rect = New-Object BoltsparkMeshImportApi+RECT
    [void][BoltsparkMeshImportApi]::GetClientRect($window, [ref]$rect)
    $consoleY = $rect.Bottom - 20 - 160
    $contentY = $consoleY + 24
    $consoleX = 254
    $consoleWidth = $rect.Right - 584
    $addX = $consoleX + $consoleWidth - 64 + 27
    $addY = $contentY + 13

    # Add menu row 4: Import Mesh...
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 45) ($contentY + 26 + 102)
    $objLog = Wait-For '\[probe\] mesh import completed count=1' 10 'OBJ import did not complete'
    if ($objLog -notmatch '\[probe\] file dialog open title="Import Mesh"') {
        throw 'Mesh import did not reach the native picker call site.'
    }
    if ($objLog -notmatch '\[mesh-library\] loaded source=Content/Probe Mesh\.obj') {
        throw 'Imported OBJ was not parsed into the mesh library.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Content\Probe Mesh.obj'))) {
        throw 'Imported OBJ was not copied into the project.'
    }

    # Second import: glTF.
    Send-Pick 2 @($sourceGltf)
    Send-Click $window $addX $addY
    Start-Sleep -Milliseconds 200
    Send-Click $window ($addX + 45) ($contentY + 26 + 102)
    $gltfLog = Wait-For '\[probe\] mesh import completed count=1 folder=' 10 'glTF import did not complete'
    if ($gltfLog -notmatch '\[mesh-library\] loaded source=Content/Probe Mesh\.gltf') {
        throw 'Imported glTF was not parsed into the mesh library.'
    }
    if (-not (Test-Path (Join-Path $workspace 'Content\Probe Mesh.gltf'))) {
        throw 'Imported glTF was not copied into the project.'
    }
    if ((Read-Log) -notmatch '\[probe\] asset browser asset row=Probe Mesh') {
        throw 'Asset Browser did not list the imported meshes.'
    }

    Set-Content -LiteralPath $closeAnswer -Value 'yes' -Encoding ascii
    [void][BoltsparkMeshImportApi]::PostMessage(
        $window, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        throw 'Editor did not close cleanly after mesh import probe.'
    }
    $process = $null
    if ((Get-Item $stderr).Length -ne 0) {
        throw "Mesh import probe wrote stderr; inspect $stderr."
    }

    Write-Host '[import-meshes] OBJ and glTF imports copied, parsed, registered, and listed in the browser.' -ForegroundColor Green
    Write-Host "[import-meshes] Evidence: $outputDir"
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
    }
    $env:BOLTSPARK_PROBE = $oldProbe
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:BOLTSPARK_PROBE_CLOSE_ANSWER = $oldAnswer
    $env:BOLTSPARK_PROBE_UNTITLED_DIR = $oldUntitled
    $env:BOLTSPARK_PROBE_PICKER_DIR = $oldPickerDir
}
