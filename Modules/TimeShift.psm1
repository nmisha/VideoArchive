Set-StrictMode -Version Latest

function ConvertTo-VideoTimeShift {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value.Trim() -notmatch '^([+-])(\d{1,6}):([0-5]\d):([0-5]\d)$') {
        throw 'Time shift must be signed HH:MM:SS, for example +03:00:00 or -01:30:00.'
    }
    $seconds = [long]$Matches[2] * 3600 + [int]$Matches[3] * 60 + [int]$Matches[4]
    if ($seconds -eq 0) { throw 'Time shift must not be zero.' }
    if ($Matches[1] -eq '-') { $seconds = -$seconds }
    return [timespan]::FromSeconds($seconds)
}

function Invoke-TimeShiftRemux {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$CreationTime,
        [Parameter(Mandatory)][string]$FfmpegPath
    )

    $arguments = @('-hide_banner', '-loglevel', 'error', '-nostdin', '-n',
        '-i', $SourcePath, '-map', '0', '-map_metadata', '0', '-map_chapters', '0',
        '-c', 'copy', '-metadata', "creation_time=$CreationTime",
        '-metadata:s', "creation_time=$CreationTime")
    # Replace common textual aliases as well as the container creation field.
    # Otherwise copied Matroska / Apple tags may still expose the old date.
    foreach ($tag in @('date', 'DATE_RECORDED', 'DATE_ENCODED', 'DATE_TAGGED', 'com.apple.quicktime.creationdate')) {
        $arguments += @('-metadata', "$tag=$CreationTime", '-metadata:s', "$tag=$CreationTime")
    }
    $arguments += $OutputPath
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $FfmpegPath @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "Time shift remux failed: $output" }
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf) -or (Get-Item -LiteralPath $OutputPath).Length -eq 0) {
        throw 'Remux produced no output.'
    }
}

Export-ModuleMember -Function ConvertTo-VideoTimeShift, Invoke-TimeShiftRemux
