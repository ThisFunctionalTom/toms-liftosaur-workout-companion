param(
    [string]$SdkPath,

    [string]$DeveloperKey,

    [string]$Version
)

if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'Version must be a three-part numeric version, such as 1.2.3.'
}

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
$outputName = if ([string]::IsNullOrWhiteSpace($Version)) {
    'TomsLiftosaurWorkoutCompanion.iq'
} else {
    "TomsLiftosaurWorkoutCompanion-v$Version.iq"
}
$outputPath = Join-Path $outputDir $outputName
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
$tempManifestPath = $null
$tempJunglePath = $null
if (-not [string]::IsNullOrWhiteSpace($Version)) {
    $manifest = New-Object System.Xml.XmlDocument
    $manifest.PreserveWhitespace = $true
    $manifest.Load((Join-Path $PSScriptRoot 'manifest.xml'))
    $application = $manifest.SelectSingleNode("//*[local-name()='application']")
    if ($null -eq $application) {
        throw 'Could not find the application element in manifest.xml.'
    }
    $application.SetAttribute('version', $Version)

    $tempManifestPath = Join-Path ([System.IO.Path]::GetTempPath()) "TomsLiftosaurManifest-$PID-$([guid]::NewGuid().ToString('N')).xml"
    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = [System.Xml.XmlWriter]::Create($tempManifestPath, $writerSettings)
    try {
        $manifest.Save($writer)
    } finally {
        $writer.Dispose()
    }

    $tempJunglePath = Join-Path ([System.IO.Path]::GetTempPath()) "TomsLiftosaurJungle-$PID-$([guid]::NewGuid().ToString('N')).jungle"
    $manifestPath = Join-Path $PSScriptRoot 'manifest.xml'
    $jungle = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'monkey.jungle') -Raw
    $jungle = $jungle.Replace('project.manifest = manifest.xml', "project.manifest = $tempManifestPath")
    $jungle = $jungle.Replace('base.sourcePath = source', "base.sourcePath = $(Join-Path $PSScriptRoot 'source')")
    $jungle = $jungle.Replace('base.resourcePath = resources', "base.resourcePath = $(Join-Path $PSScriptRoot 'resources')")
    Set-Content -LiteralPath $tempJunglePath -Value $jungle -NoNewline -Encoding utf8
    $compilerArgs[1] = $tempJunglePath
}

try {
    & $compilerPath @compilerArgs
    $compileExitCode = $LASTEXITCODE

    if ($compileExitCode -ne 0) {
        throw "Monkey C packaging failed with exit code $compileExitCode."
    }
    if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        throw "Packaging completed without producing $outputPath"
    }
} finally {
    foreach ($tempPath in @($tempManifestPath, $tempJunglePath)) {
        if ($null -ne $tempPath -and (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

Write-Output "Packaged fēnix 5 release: $outputPath"
