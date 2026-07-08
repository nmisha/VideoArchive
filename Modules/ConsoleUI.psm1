Set-StrictMode -Version Latest

$script:InlineTelemetryActive = $false
$script:CurrentEncodeRemain = $null

function Format-UiDuration {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return 'n/a'
    }

    $duration = if ($Value -is [TimeSpan]) {
        [TimeSpan]$Value
    } elseif ($Value -is [System.Nullable[TimeSpan]]) {
        if (-not $Value.HasValue) {
            return 'n/a'
        }
        $Value.Value
    } else {
        try {
            [TimeSpan]$Value
        } catch {
            return 'n/a'
        }
    }

    if ($duration.TotalHours -ge 1) {
        return $duration.ToString('hh\:mm\:ss')
    }

    return $duration.ToString('mm\:ss')
}

function Format-UiSize {
    param(
        $Megabytes
    )

    if ($null -eq $Megabytes) {
        return 'n/a'
    }

    $sizeMb = try {
        [double]$Megabytes
    } catch {
        return 'n/a'
    }

    if ($sizeMb -ge 1024) {
        return ('{0:N2} GB' -f ($sizeMb / 1024))
    }

    return ('{0:N2} MB' -f $sizeMb)
}

function New-UiProgressBar {
    param(
        [int]$Percent,
        [int]$Width = 24
    )

    $safePercent = [math]::Max(0, [math]::Min(100, $Percent))
    $filled = [math]::Round(($safePercent / 100) * $Width)
    $filledText = ''.PadLeft($filled, '#')
    $emptyText = ''.PadLeft(($Width - $filled), '-')
    return ('[{0}{1}]' -f $filledText, $emptyText)
}

function Complete-InlineTelemetry {
    if ($script:InlineTelemetryActive) {
        Write-Host ''
        $script:InlineTelemetryActive = $false
    }
}

function Reset-EncodeTelemetryState {
    $script:CurrentEncodeRemain = $null
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
    $presetCount = @($PresetCatalog.Presets).Count
    for ($index = 0; $index -lt $presetCount; $index++) {
        $preset = $PresetCatalog.Presets[$index]
        $suffix = if ($preset.IsDefault) { ' [default]' } else { '' }
        Write-Host ("{0}. {1} - {2}{3}" -f ($index + 1), $preset.Name, $preset.Description, $suffix)
    }

    Write-Host ''
    $selection = Read-Host ("Select preset (1-{0}) or press Enter for {1}" -f $presetCount, $PresetCatalog.DefaultPreset)
    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $PresetCatalog.DefaultPreset
    }

    $parsedIndex = 0
    if ([int]::TryParse($selection, [ref]$parsedIndex)) {
        if ($parsedIndex -ge 1 -and $parsedIndex -le $presetCount) {
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

function Select-VideoArchiveEncoderChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$AvailableBackends,

        [Parameter(Mandatory)]
        [string[]]$AvailableCodecs,

        [string]$RecommendedBackend = 'auto',

        [string]$RecommendedCodec = 'hevc'
    )

    Complete-InlineTelemetry
    Write-Host 'NVIDIA RTX GPU was not detected.' -ForegroundColor Yellow
    Write-Host 'Select encoder backend and codec for this run.' -ForegroundColor Yellow
    Write-Host ''

    $backendChoices = @('auto') + @($AvailableBackends | Where-Object { $_ -ne 'auto' })
    Write-Host 'Available encoder backends:' -ForegroundColor Cyan
    $backendChoiceCount = @($backendChoices).Count
    for ($index = 0; $index -lt $backendChoiceCount; $index++) {
        $backend = $backendChoices[$index]
        $suffix = if ($backend -eq $RecommendedBackend) { ' [default]' } else { '' }
        Write-Host ("{0}. {1}{2}" -f ($index + 1), $backend, $suffix)
    }

    Write-Host ''
    $backendSelection = Read-Host ("Select backend (1-{0}) or press Enter for {1}" -f $backendChoiceCount, $RecommendedBackend)
    $selectedBackend = $RecommendedBackend
    if (-not [string]::IsNullOrWhiteSpace($backendSelection)) {
        $parsedBackendIndex = 0
        if ([int]::TryParse($backendSelection, [ref]$parsedBackendIndex) -and $parsedBackendIndex -ge 1 -and $parsedBackendIndex -le $backendChoiceCount) {
            $selectedBackend = $backendChoices[$parsedBackendIndex - 1]
        } elseif ($backendChoices -contains $backendSelection.Trim().ToLowerInvariant()) {
            $selectedBackend = $backendSelection.Trim().ToLowerInvariant()
        } else {
            throw "Invalid encoder backend selection: $backendSelection"
        }
    }

    $codecChoices = @($AvailableCodecs)
    Write-Host ''
    Write-Host 'Available output codecs:' -ForegroundColor Cyan
    $codecChoiceCount = @($codecChoices).Count
    for ($index = 0; $index -lt $codecChoiceCount; $index++) {
        $codec = $codecChoices[$index]
        $suffix = if ($codec -eq $RecommendedCodec) { ' [default]' } else { '' }
        Write-Host ("{0}. {1}{2}" -f ($index + 1), $codec.ToUpperInvariant(), $suffix)
    }

    if ($codecChoices -contains 'av1') {
        Write-Host 'Note: HDR AV1 is disabled by default and falls back to HEVC unless enabled in config.' -ForegroundColor DarkYellow
    }

    Write-Host ''
    $codecSelection = Read-Host ("Select codec (1-{0}) or press Enter for {1}" -f $codecChoiceCount, $RecommendedCodec.ToUpperInvariant())
    $selectedCodec = $RecommendedCodec
    if (-not [string]::IsNullOrWhiteSpace($codecSelection)) {
        $parsedCodecIndex = 0
        if ([int]::TryParse($codecSelection, [ref]$parsedCodecIndex) -and $parsedCodecIndex -ge 1 -and $parsedCodecIndex -le $codecChoiceCount) {
            $selectedCodec = $codecChoices[$parsedCodecIndex - 1]
        } elseif ($codecChoices -contains $codecSelection.Trim().ToLowerInvariant()) {
            $selectedCodec = $codecSelection.Trim().ToLowerInvariant()
        } else {
            throw "Invalid output codec selection: $codecSelection"
        }
    }

    [pscustomobject]@{
        Backend = $selectedBackend
        Codec = $selectedCodec
    }
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

function Write-DecisionStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Encode', 'Encoded', 'Skip', 'Failed', 'DryRun', 'Discarded', 'Resume')]
        [string]$Action = 'Encode'
    )

    $color = switch ($Action) {
        'Encode' { 'Gray' }
        'Encoded' { 'Green' }
        'Skip' { 'Yellow' }
        'DryRun' { 'Cyan' }
        'Discarded' { 'DarkYellow' }
        'Resume' { 'DarkCyan' }
        'Failed' { 'Red' }
        default { 'Gray' }
    }

    Complete-InlineTelemetry
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
        [datetime]$StartTime,

        [Nullable[double]]$ProcessedSourceMb,
        [Nullable[double]]$TotalSourceMb,

        [int]$Encoded = 0,

        [int]$Skipped = 0,

        [int]$Failed = 0,

        [int]$DryRun = 0,

        [int]$ResumeSkipped = 0
    )

    $percent = if ($Total -gt 0) { [int](($Completed / $Total) * 100) } else { 0 }
    $progressBar = New-UiProgressBar -Percent $percent
    $elapsed = (Get-Date) - $StartTime
    $etaText = 'n/a'
    $avgText = 'n/a'
    $countText = "E:$Encoded S:$Skipped F:$Failed D:$DryRun"
    if ($ResumeSkipped -gt 0) {
        $countText += " R:$ResumeSkipped"
    }

    if ($Completed -gt 0 -and $Completed -lt $Total) {
        $avgSeconds = $elapsed.TotalSeconds / $Completed
        $remaining = [TimeSpan]::FromSeconds($avgSeconds * ($Total - $Completed))
        $etaText = Format-UiDuration -Value $remaining
        $avgText = Format-UiDuration -Value ([TimeSpan]::FromSeconds($avgSeconds))
    } elseif ($Completed -gt 0) {
        $avgText = Format-UiDuration -Value ([TimeSpan]::FromSeconds($elapsed.TotalSeconds / $Completed))
    }

    Complete-InlineTelemetry
    $sizeText = if ($null -ne $ProcessedSourceMb -and $null -ne $TotalSourceMb -and $TotalSourceMb -gt 0) {
        " | Size {0}/{1}" -f (Format-UiSize -Megabytes $ProcessedSourceMb), (Format-UiSize -Megabytes $TotalSourceMb)
    } else {
        ''
    }
    Write-Host ("Progress: {0} {1}/{2} ({3}%) | ETA {4} | Avg/File {5} | {6}{7}" -f $progressBar, $Completed, $Total, $percent, $etaText, $avgText, $countText, $sizeText) -ForegroundColor DarkCyan
    Write-Host ("Current : {0}" -f $CurrentFile) -ForegroundColor DarkGray
}

function Write-FileResultStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName,

        [string]$Action,

        [Nullable[double]]$SourceSizeMb,

        [Nullable[double]]$OutputSizeMb,

        [Nullable[double]]$SavingsPercent,

        [Nullable[TimeSpan]]$Duration
    )

    $actionText = if ([string]::IsNullOrWhiteSpace($Action)) { 'Result' } else { $Action }
    $sizeText = "{0} -> {1}" -f (Format-UiSize -Megabytes $SourceSizeMb), (Format-UiSize -Megabytes $OutputSizeMb)
    $savingsText = if ($null -ne $SavingsPercent) { ('{0:N2}%' -f $SavingsPercent) } else { 'n/a' }
    $durationText = Format-UiDuration -Value $Duration
    $uiAction = switch ($actionText) {
        'Encoded' { 'Encoded' }
        'Discarded' { 'Discarded' }
        'Failed' { 'Failed' }
        default { 'Encoded' }
    }
    Write-DecisionStatus -Message ("{0}: {1} | {2} | Saved {3} | Time {4}" -f $actionText, $FileName, $sizeText, $savingsText, $durationText) -Action $uiAction
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
        [psobject]$Telemetry,

        [int]$Completed = 0,

        [int]$Total = 0,

        [Nullable[datetime]]$StartTime,

        [int]$Encoded = 0,

        [int]$Skipped = 0,

        [int]$Failed = 0,

        [int]$DryRun = 0,

        [int]$ResumeSkipped = 0
    )

    $currentRemain = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$Telemetry.RemainText)) {
        try {
            $currentRemain = [TimeSpan]::Parse([string]$Telemetry.RemainText)
            $script:CurrentEncodeRemain = $currentRemain
        } catch {
        }
    }

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

    $totalEtaText = 'n/a'
    if ($null -ne $StartTime -and $Total -gt 0) {
        $remainingAfterCurrent = [math]::Max(($Total - $Completed - 1), 0)
        $resolvedStartTime = if ($StartTime -is [datetime]) {
            [datetime]$StartTime
        } elseif ($StartTime -is [System.Nullable[datetime]]) {
            if (-not $StartTime.HasValue) {
                $null
            } else {
                $StartTime.Value
            }
        } else {
            try {
                [datetime]$StartTime
            } catch {
                $null
            }
        }

        if ($Completed -gt 0 -and $null -ne $currentRemain) {
            $elapsed = (Get-Date) - $resolvedStartTime
            $avgSeconds = $elapsed.TotalSeconds / $Completed
            $totalEta = $currentRemain.Add([TimeSpan]::FromSeconds($avgSeconds * $remainingAfterCurrent))
            $totalEtaText = Format-UiDuration -Value $totalEta
        } elseif ($null -ne $currentRemain -and $null -ne $resolvedStartTime) {
            $totalEtaText = Format-UiDuration -Value $currentRemain
        }
    }

    if ($totalEtaText -ne 'n/a') {
        $parts += "TotalETA $totalEtaText"
    }

    if ($null -ne $Telemetry.ElapsedText) {
        $parts += "Elapsed $($Telemetry.ElapsedText)"
    }

    $countText = "E:$Encoded S:$Skipped F:$Failed D:$DryRun"
    if ($ResumeSkipped -gt 0) {
        $countText += " R:$ResumeSkipped"
    }
    $message = 'Encoding: ' + ($parts -join ' | ') + " | $countText"
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
    if ($null -ne $Summary.PSObject.Properties['ResumeSkipped']) {
        Write-Host ("ResSkip : {0}" -f $Summary.ResumeSkipped)
    }
    Write-Host ("Failed  : {0}" -f $Summary.Failed)
    Write-Host ("DryRun  : {0}" -f $Summary.DryRun)
    Write-Host ("HDR     : {0}" -f $Summary.Hdr)
    Write-Host ("SDR     : {0}" -f $Summary.Sdr)
    Write-Host ("DateMeta: {0}" -f $Summary.CaptureDateMetadata)
    Write-Host ("DateName: {0}" -f $Summary.CaptureDateFileName)
    Write-Host ("DateMiss: {0}" -f $Summary.CaptureDateMissing)
    if ($null -ne $Summary.PSObject.Properties['TotalElapsed']) {
        Write-Host ("Elapsed : {0}" -f (Format-UiDuration -Value $Summary.TotalElapsed))
    }
    if ($null -ne $Summary.PSObject.Properties['TotalSourceMb']) {
        Write-Host ("SrcSize : {0}" -f (Format-UiSize -Megabytes $Summary.TotalSourceMb))
    }
    if ($null -ne $Summary.PSObject.Properties['TotalOutputMb']) {
        Write-Host ("OutSize : {0}" -f (Format-UiSize -Megabytes $Summary.TotalOutputMb))
    }
    if ($null -ne $Summary.PSObject.Properties['TotalSavingsPercent']) {
        Write-Host ("Savings : {0}" -f ('{0:N2}%' -f $Summary.TotalSavingsPercent))
    }
    if ($null -ne $Summary.PSObject.Properties['AverageEncodedSavingsPercent']) {
        Write-Host ("AvgSave : {0}" -f ('{0:N2}%' -f $Summary.AverageEncodedSavingsPercent))
    }
    if ($null -ne $Summary.PSObject.Properties['FilesPerMinute']) {
        Write-Host ("Rate    : {0:N2} files/min" -f $Summary.FilesPerMinute)
    }
}

Export-ModuleMember -Function Show-VideoArchiveBanner, Select-VideoArchivePreset, Select-VideoArchiveEncoderChoice, Write-VideoArchiveStatus, Write-DecisionStatus, Write-CaptureDateStatus, Update-VideoArchiveProgress, Update-EncodeTelemetry, Complete-VideoArchiveProgress, Show-VideoArchiveSummary, Write-FileResultStatus, Reset-EncodeTelemetryState
