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

function Select-VideoArchivePreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$PresetCatalog
    )

    Write-Host 'Available presets:' -ForegroundColor Cyan
    for ($index = 0; $index -lt $PresetCatalog.Presets.Count; $index++) {
        $preset = $PresetCatalog.Presets[$index]
        $suffix = if ($preset.IsDefault) { ' [default]' } else { '' }
        Write-Host ("{0}. {1} - {2}{3}" -f ($index + 1), $preset.Name, $preset.Description, $suffix)
    }

    Write-Host ''
    $selection = Read-Host ("Select preset (1-{0}) or press Enter for {1}" -f $PresetCatalog.Presets.Count, $PresetCatalog.DefaultPreset)
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $PresetCatalog.DefaultPreset
    }

    $parsedIndex = 0
    if ([int]::TryParse($selection, [ref]$parsedIndex)) {
        if ($parsedIndex -ge 1 -and $parsedIndex -le $PresetCatalog.Presets.Count) {
            return $PresetCatalog.Presets[$parsedIndex - 1].Name
        }
    }

    foreach ($preset in $PresetCatalog.Presets) {
        if ($preset.Name -ieq $selection.Trim()) {
            return $preset.Name
        }
    }

    throw "Invalid preset selection: $selection"
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

    Write-Host ("Progress: {0}/{1} ({2}%) | ETA {3} | {4}" -f $Current, $Total, $percent, $etaText, $CurrentFile) -ForegroundColor DarkCyan
}

function Complete-VideoArchiveProgress {
    [CmdletBinding()]
    param()
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

Export-ModuleMember -Function Show-VideoArchiveBanner, Select-VideoArchivePreset, Write-VideoArchiveStatus, Update-VideoArchiveProgress, Complete-VideoArchiveProgress, Show-VideoArchiveSummary
