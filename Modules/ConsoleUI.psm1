Set-StrictMode -Version Latest

function Show-VideoArchiveBanner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config
    )

    Write-Host ''
    Write-Host "$($Config.AppName) MVP v1.0" -ForegroundColor Cyan
    Write-Host "Preset: $($Config.PresetName)" -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-VideoArchiveStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        default { 'Gray' }
    }

    Write-Host $Message -ForegroundColor $color
}

function Update-VideoArchiveProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Current,

        [Parameter(Mandatory)]
        [int]$Total,

        [Parameter(Mandatory)]
        [string]$CurrentFile,

        [Parameter(Mandatory)]
        [datetime]$StartTime
    )

    $percent = if ($Total -gt 0) { [int](($Current / $Total) * 100) } else { 0 }
    $elapsed = (Get-Date) - $StartTime
    $etaText = 'n/a'

    if ($Current -gt 0 -and $Current -lt $Total) {
        $avgSeconds = $elapsed.TotalSeconds / $Current
        $remaining = [TimeSpan]::FromSeconds($avgSeconds * ($Total - $Current))
        $etaText = $remaining.ToString('hh\:mm\:ss')
    }

    Write-Progress -Activity 'VideoArchive' -Status "$Current / $Total | ETA $etaText | $CurrentFile" -PercentComplete $percent
}

function Complete-VideoArchiveProgress {
    [CmdletBinding()]
    param()

    Write-Progress -Activity 'VideoArchive' -Completed
}

function Show-VideoArchiveSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Summary
    )

    Write-Host ''
    Write-Host 'Summary' -ForegroundColor Cyan
    Write-Host ("Encoded : {0}" -f $Summary.Encoded)
    Write-Host ("Skipped : {0}" -f $Summary.Skipped)
    Write-Host ("Failed  : {0}" -f $Summary.Failed)
    Write-Host ("DryRun  : {0}" -f $Summary.DryRun)
    Write-Host ("HDR     : {0}" -f $Summary.Hdr)
    Write-Host ("SDR     : {0}" -f $Summary.Sdr)
}

Export-ModuleMember -Function Show-VideoArchiveBanner, Write-VideoArchiveStatus, Update-VideoArchiveProgress, Complete-VideoArchiveProgress, Show-VideoArchiveSummary
