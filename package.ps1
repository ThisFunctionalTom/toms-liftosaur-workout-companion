param(
    [string]$SdkPath,

    [string]$DeveloperKey
)

if ([string]::IsNullOrWhiteSpace($DeveloperKey)) {
    $DeveloperKey = Join-Path $HOME '.garmin/developer_key'
}

if ([string]::IsNullOrWhiteSpace($SdkPath)) {
    $sdkConfigPath = Join-Path $env:APPDATA 'Garmin/ConnectIQ/current-sdk.cfg'
    if (-not (Test-Path -LiteralPath $sdkConfigPath -PathType Leaf)) {
        throw "Could not find the active SDK config at $sdkConfigPath. Install/select an SDK in Garmin Connect IQ SDK Manager, or pass -SdkPath explicitly."
    }

    $SdkPath = (Get-Content -LiteralPath $sdkConfigPath -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($SdkPath)) {
        throw "The active SDK config is empty: $sdkConfigPath"
    }
}

$SdkPath = [System.IO.Path]::GetFullPath($SdkPath)
$compilerPath = Join-Path $SdkPath 'bin/monkeyc.bat'
if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    $compilerPath = Join-Path $SdkPath 'bin/monkeyc.exe'
}
if (-not (Test-Path -LiteralPath $compilerPath -PathType Leaf)) {
    throw "Could not find the Monkey C compiler launcher (monkeyc.bat or monkeyc.exe) in $SdkPath\bin."
}
if (-not (Test-Path -LiteralPath $DeveloperKey -PathType Leaf)) {
    throw "Could not find the developer key at $DeveloperKey"
}

$outputDir = Join-Path $PSScriptRoot 'bin'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$outputPath = Join-Path $outputDir 'LiftosaurWorkout.iq'
if (Test-Path -LiteralPath $outputPath) {
    Remove-Item -LiteralPath $outputPath -Force
}

$compilerArgs = @(
    '-f', (Join-Path $PSScriptRoot 'monkey.jungle'),
    '-d', 'fenix5',
    '-y', $DeveloperKey,
    '-e',
    '-r',
    '-o', $outputPath
)
& $compilerPath @compilerArgs
$compileExitCode = $LASTEXITCODE

if ($compileExitCode -ne 0) {
    exit $compileExitCode
}
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw "Packaging completed without producing $outputPath"
}

Write-Output "Packaged fēnix 5 release: $outputPath"
