param(
    [switch]$Unregister,
    [switch]$Check
)

# Opt-in, user-level registration so double-clicking a .boltproject file
# launches the packaged editor with that project, like Unreal's .uproject.
# It only writes HKCU\Software\Classes (no admin, no system-wide install).
# Nothing here runs automatically during a build or editor launch.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$executable = Join-Path $repoRoot 'release\Boltspark.exe'
$extension = '.boltproject'
$progId = 'Boltspark.Project.1'
$classRoot = 'HKCU:\Software\Classes'

function Get-RegisteredValue([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    return (Get-Item -LiteralPath $path).GetValue('')
}

if ($Check) {
    [pscustomobject]@{
        Extension = $extension
        ProgId = Get-RegisteredValue "$classRoot\$extension"
        Command = Get-RegisteredValue "$classRoot\$progId\shell\open\command"
        Executable = $executable
        ExecutableExists = Test-Path $executable
    } | Format-List
    return
}

if ($Unregister) {
    Remove-Item -LiteralPath "$classRoot\$extension" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath "$classRoot\$progId" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Boltspark .boltproject association removed (user-level).' -ForegroundColor Green
    return
}

if (-not (Test-Path $executable)) {
    throw "Packaged editor not found: $executable. Run tools\build.ps1 first."
}

New-Item -Path "$classRoot\$extension" -Force | Out-Null
Set-Item -LiteralPath "$classRoot\$extension" -Value $progId

New-Item -Path "$classRoot\$progId" -Force | Out-Null
Set-Item -LiteralPath "$classRoot\$progId" -Value 'Boltspark Project'
New-ItemProperty -LiteralPath "$classRoot\$progId" -Name 'FriendlyName' `
    -Value 'Boltspark Project' -PropertyType String -Force | Out-Null

New-Item -Path "$classRoot\$progId\DefaultIcon" -Force | Out-Null
Set-Item -LiteralPath "$classRoot\$progId\DefaultIcon" -Value "`"$executable`",0"

New-Item -Path "$classRoot\$progId\shell\open\command" -Force | Out-Null
Set-Item -LiteralPath "$classRoot\$progId\shell\open\command" `
    -Value "`"$executable`" `"%1`""

Write-Host "Registered .boltproject -> $executable (user-level, opt-in)." -ForegroundColor Green
Write-Host 'Use -Unregister to remove the association, -Check to inspect it.' -ForegroundColor Gray
