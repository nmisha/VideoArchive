Set-StrictMode -Version Latest

$script:InlineTelemetryActive = $false

function Complete-InlineTelemetry {
    if ($script:InlineTelemetryActive) {
        Write-Host ''
        $script:InlineTelemetryActive = $false
    }
}

function Show-VideoArchiveBanner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config
    )

    Complete-InlineTelemetry
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

    Complete-InlineTelemetry
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

    Complete-InlineTelemetry
    $color = switch ($Level) {
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
        default { 'Gray' }
    }

    Write-Host $Message -ForegroundColor $color
}

function Write-CaptureDateStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [Parameter(Mandatory)]
        [psobject]$CaptureDateResult
    )

    $dateText = if ($CaptureDateResult.Success -and $null -ne $CaptureDateResult.DateTime) {
        $CaptureDateResult.DateTime.ToString('yyyy-MM-dd HH:mm:ss')
    } else {
        'n/a'
    }

    $sourceText = if ([string]::IsNullOrWhiteSpace([string]$CaptureDateResult.Source)) {
        'None'
    } else {
        [string]$CaptureDateResult.Source
    }

    Write-VideoArchiveStatus -Message ("CaptureDate: {0} | Source: {1} | File: {2}" -f $dateText, $sourceText, $FileName) -Level $(if ($CaptureDateResult.Success) { 'Info' } else { 'Warn' })
}

function Update-VideoArchiveProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Current,

        [Parameter(Mandatory)]
        [int]$Total,

        [Parameter(Mandatory)]
        [int]$Completed,

        [Parameter(Mandatory)]
        [string]$CurrentFile,

        [Parameter(Mandatory)]
        [datetime]$StartTime
    )

    $percent = if ($Total -gt 0) { [int](($Completed / $Total) * 100) } else { 0 }
    $elapsed = (Get-Date) - $StartTime
    $etaText = 'n/a'

    if ($Completed -gt 0 -and $Completed -lt $Total) {
        $avgSeconds = $elapsed.TotalSeconds / $Completed
        $remaining = [TimeSpan]::FromSeconds($avgSeconds * ($Total - $Completed))
        $etaText = $remaining.ToString('hh\:mm\:ss')
    }

    Complete-InlineTelemetry
    Write-Host ("Progress: {0}/{1} completed ({2}%) | ETA {3} | Current: {4}" -f $Completed, $Total, $percent, $etaText, $CurrentFile) -ForegroundColor DarkCyan
}

function Complete-VideoArchiveProgress {
    [CmdletBinding()]
    param()

    Complete-InlineTelemetry
}

function Update-EncodeTelemetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Telemetry
    )

    $parts = @()
    if ($null -ne $Telemetry.PercentText) {
        $parts += $Telemetry.PercentText
    }

    if ($null -ne $Telemetry.FrameText) {
        $parts += $Telemetry.FrameText
    }

    if ($null -ne $Telemetry.FpsText) {
        $parts += "FPS $($Telemetry.FpsText)"
    }

    if ($null -ne $Telemetry.RemainText) {
        $parts += "ETA $($Telemetry.RemainText)"
    }

    if ($null -ne $Telemetry.ElapsedText) {
        $parts += "Elapsed $($Telemetry.ElapsedText)"
    }

    $message = 'Encoding: ' + ($parts -join ' | ')
    Write-Host -NoNewline ("`r{0}   " -f $message) -ForegroundColor DarkYellow
    $script:InlineTelemetryActive = $true
}

function Show-VideoArchiveSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Summary
    )

    Complete-InlineTelemetry
    Write-Host ''
    Write-Host 'Summary' -ForegroundColor Cyan
    Write-Host ("Encoded : {0}" -f $Summary.Encoded)
    Write-Host ("Skipped : {0}" -f $Summary.Skipped)
    Write-Host ("Failed  : {0}" -f $Summary.Failed)
    Write-Host ("DryRun  : {0}" -f $Summary.DryRun)
    Write-Host ("HDR     : {0}" -f $Summary.Hdr)
    Write-Host ("SDR     : {0}" -f $Summary.Sdr)
    Write-Host ("DateMeta: {0}" -f $Summary.CaptureDateMetadata)
    Write-Host ("DateName: {0}" -f $Summary.CaptureDateFileName)
    Write-Host ("DateMiss: {0}" -f $Summary.CaptureDateMissing)
}

Export-ModuleMember -Function Show-VideoArchiveBanner, Select-VideoArchivePreset, Write-VideoArchiveStatus, Write-CaptureDateStatus, Update-VideoArchiveProgress, Update-EncodeTelemetry, Complete-VideoArchiveProgress, Show-VideoArchiveSummary
