param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$SdkPath,

    [string]$DeveloperKey
)

$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw 'Version must be a three-part numeric version, such as 1.2.3.'
}

Push-Location $PSScriptRoot
try {
    $jj = Get-Command jj -ErrorAction Stop
    $changeStatus = & $jj.Source log -r '@' -T 'empty' --no-graph 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not inspect the current Jujutsu change: $changeStatus"
    }
    if (($changeStatus | Out-String).Trim() -ne 'false') {
        throw 'The current Jujutsu change is empty. Add a release description and ensure the changes to release are in the current change.'
    }
    $changeDescription = & $jj.Source log -r '@' -T 'description.first_line()' --no-graph 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read the current Jujutsu change description: $changeDescription"
    }
    if ([string]::IsNullOrWhiteSpace(($changeDescription | Out-String).Trim())) {
        throw 'The current Jujutsu change has no description. Describe the release change before tagging it.'
    }

    $tagName = "v$Version"
    $existingTags = & $jj.Source tag list -T 'name_placeholder ++ "\n"' $tagName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not check whether Jujutsu tag $tagName exists: $existingTags"
    }
    $tagOutput = ($existingTags | Out-String).Trim()
    if ($tagOutput -split "`r?`n" | Where-Object { $_ -eq $tagName }) {
        throw "Jujutsu tag $tagName already exists. Choose a new version."
    }

    $testArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($SdkPath)) {
        $testArgs.SdkPath = $SdkPath
    }
    try {
        & (Join-Path $PSScriptRoot 'run-tests.ps1') @testArgs
    } catch {
        throw "Simulator tests failed: $($_.Exception.Message)"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Simulator tests failed with exit code $LASTEXITCODE."
    }

    $packageArgs = @{
        Version = $Version
    }
    if (-not [string]::IsNullOrWhiteSpace($SdkPath)) {
        $packageArgs.SdkPath = $SdkPath
    }
    if (-not [string]::IsNullOrWhiteSpace($DeveloperKey)) {
        $packageArgs.DeveloperKey = $DeveloperKey
    }
    try {
        & (Join-Path $PSScriptRoot 'package.ps1') @packageArgs
    } catch {
        throw "Packaging failed: $($_.Exception.Message)"
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Packaging failed with exit code $LASTEXITCODE."
    }

    & $jj.Source tag set $tagName -r '@'
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create Jujutsu tag $tagName."
    }

    Write-Output "Released $tagName as bin/TomsLiftosaurWorkoutCompanion-$tagName.iq"
} finally {
    Pop-Location
}
