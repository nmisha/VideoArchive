param(
    [string]$InputPath,
    [string]$Preset,
    [switch]$Force,
    [switch]$NoSmartSkip,
    [switch]$DryRun
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Join-Path -Path $projectRoot -ChildPath 'Modules'

$requiredModules = @(
    'Config.psm1',
    'Scanner.psm1',
    'MediaAnalyzer.psm1',
    'DecisionEngine.psm1',
    'Encoder.psm1',
    'DateResolver.psm1',
    'Metadata.psm1',
    'Logger.psm1',
    'ConsoleUI.psm1',
    'Validator.psm1'
)

foreach ($module in $requiredModules) {
    Import-Module (Join-Path -Path $moduleRoot -ChildPath $module) -Force
}

$tempRoot = $null

function New-VideoArchiveRecord {
    param(
        [string]$SourcePath,
        [string]$OutputPath,
        [string]$Action,
        [string]$Reason,
        [string]$OutputGroup,
        [string]$Codec,
        [Nullable[double]]$BitrateMbps,
        [bool]$IsHdr,
        [string]$HdrType,
        [Nullable[double]]$SourceSizeMb,
        [Nullable[double]]$OutputSizeMb,
        [Nullable[double]]$SavingsPercent,
        [bool]$ValidationPassed,
        [string]$ValidationWarnings,
        [string]$ValidationErrors,
        [string]$Duration,
        [bool]$DryRunFlag,
        [string]$HdrTypeSource,
        [string]$HdrTypeOutput,
        [Nullable[int]]$SourceWidth,
        [Nullable[int]]$SourceHeight,
        [Nullable[int]]$OutputWidth,
        [Nullable[int]]$OutputHeight,
        [string]$SourceTransfer,
        [string]$OutputTransfer,
        [string]$SourcePrimaries,
        [string]$OutputPrimaries,
        [Nullable[int]]$SourceBitDepth,
        [Nullable[int]]$OutputBitDepth,
        [string]$CaptureDate,
        [string]$CaptureDateSource,
        [string]$CaptureDatePattern,
        [bool]$CaptureDateRecognized = $false,
        [string]$CaptureDateWarnings,
        [bool]$StrictDateMode = $false,
        [bool]$DateValidationSuccess = $false
    )

    [pscustomobject][ordered]@{
        Timestamp = Get-Date -Format 's'
        SourcePath = $SourcePath
        OutputPath = $OutputPath
        Action = $Action
        Reason = $Reason
        OutputGroup = $OutputGroup
        Codec = $Codec
        BitrateMbps = $BitrateMbps
        IsHdr = $IsHdr
        HdrType = $HdrType
        SourceSizeMb = $SourceSizeMb
        OutputSizeMb = $OutputSizeMb
        SavingsPercent = $SavingsPercent
        ValidationSuccess = $ValidationPassed
        ValidationWarnings = $ValidationWarnings
        ValidationErrors = $ValidationErrors
        Duration = $Duration
        DryRun = $DryRunFlag
        HdrTypeSource = $HdrTypeSource
        HdrTypeOutput = $HdrTypeOutput
        SourceWidth = $SourceWidth
        SourceHeight = $SourceHeight
        OutputWidth = $OutputWidth
        OutputHeight = $OutputHeight
        SourceTransfer = $SourceTransfer
        OutputTransfer = $OutputTransfer
        SourcePrimaries = $SourcePrimaries
        OutputPrimaries = $OutputPrimaries
        SourceBitDepth = $SourceBitDepth
        OutputBitDepth = $OutputBitDepth
        CaptureDate = $CaptureDate
        CaptureDateSource = $CaptureDateSource
        CaptureDatePattern = $CaptureDatePattern
        CaptureDateRecognized = $CaptureDateRecognized
        CaptureDateWarnings = $CaptureDateWarnings
        StrictDateMode = $StrictDateMode
        DateValidationSuccess = $DateValidationSuccess
    }
}

function Get-OutputRoots {
    param(
        [Parameter(Mandatory)]
        [string]$ResolvedInputPath,

        [Parameter(Mandatory)]
        [psobject]$Config
    )

    $item = Get-Item -LiteralPath $ResolvedInputPath
    $baseRoot = if ($item.PSIsContainer) { $item.FullName.TrimEnd('\') } else { $item.DirectoryName.TrimEnd('\') }

    [pscustomobject]@{
        HDR = $baseRoot + $Config.Output.HdrSuffix
        SDR = $baseRoot + $Config.Output.SdrSuffix
    }
}

function Get-TempOutputPath {
    param(
        [Parameter(Mandatory)]
        [string]$TempRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    $safeName = ($RelativePath -replace '[\\/:*?"<>|]', '_')
    return Join-Path -Path $TempRoot -ChildPath $safeName
}

function Remove-IfExists {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Normalize-InputPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $normalized = $Path.Trim()
    $normalized = $normalized.Trim('"')

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $normalized
    }

    $isDriveRoot = $normalized -match '^[a-zA-Z]:\\$'
    $isUncRoot = $normalized -match '^\\\\[^\\]+\\[^\\]+\\$'
    if (-not $isDriveRoot -and -not $isUncRoot) {
        $normalized = $normalized.TrimEnd('\')
    }

    return $normalized
}

function Get-ReadableErrorMessage {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $candidates = @(
        $ErrorRecord.Exception.Message
        $ErrorRecord.CategoryInfo.Reason
        $ErrorRecord.ToString()
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        $normalized = (($candidate -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ' | '
        if (-not [string]::IsNullOrWhiteSpace($normalized) -and $normalized -notmatch '^-{10,}$') {
            return $normalized
        }
    }

    return 'Unknown error'
}

try {
    if ([string]::IsNullOrWhiteSpace($Preset)) {
        $presetCatalog = Get-VideoArchivePresetCatalog -ProjectRoot $projectRoot
        $Preset = Select-VideoArchivePreset -PresetCatalog $presetCatalog
    }

    $config = Import-VideoArchiveConfig -ProjectRoot $projectRoot -PresetName $Preset
    Test-VideoArchiveTools -Config $config | Out-Null

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        $InputPath = Read-Host 'Enter file or folder path'
    }

    $InputPath = Normalize-InputPath -Path $InputPath

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
        throw 'Input path is required.'
    }

    $resolvedInputPath = [System.IO.Path]::GetFullPath($InputPath)
    $outputRoots = Get-OutputRoots -ResolvedInputPath $resolvedInputPath -Config $config

    $files = @(Get-VideoFiles -InputPath $resolvedInputPath -Extensions $config.Extensions)
    $logger = Initialize-VideoArchiveLogger -LogRoot $config.Output.LogsFolder
    $tempRoot = Join-Path -Path $config.Output.TempFolder -ChildPath $logger.RunId

    if (-not (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    Show-VideoArchiveBanner -Config $config
    Write-VideoArchiveStatus -Message "Input : $resolvedInputPath"
    Write-VideoArchiveStatus -Message "Files : $($files.Count)"
    Write-VideoArchiveStatus -Message "Logs  : $($logger.TxtPath)"

    Write-LogMessage -Logger $logger -Message "Run started. Input=$resolvedInputPath Preset=$($config.PresetName) Force=$Force NoSmartSkip=$NoSmartSkip DryRun=$DryRun"

    if ($files.Count -eq 0) {
        Write-VideoArchiveStatus -Message 'No supported video files found.' -Level Warn
        Write-LogMessage -Logger $logger -Message 'No supported video files found.'
        exit 0
    }

    $summary = [pscustomobject]@{
        Encoded = 0
        Skipped = 0
        Failed = 0
        DryRun = 0
        Hdr = 0
        Sdr = 0
        CaptureDateMetadata = 0
        CaptureDateFileName = 0
        CaptureDateMissing = 0
    }

    $runStart = Get-Date
    $completedCount = 0

    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        Update-VideoArchiveProgress -Current ($index + 1) -Completed $completedCount -Total $files.Count -CurrentFile $file.RelativePath -StartTime $runStart

        $tempOutputFile = $null
        $finalOutputFile = $null

        try {
            $videoInfo = Get-VideoInfo -Path $file.Path -MediaInfoPath $config.Tools.MediaInfo
            $sourceMetadata = Get-VideoMetadataSnapshot -Path $file.Path -ExifToolPath $config.Tools.ExifTool
            $captureDateResult = Resolve-VideoCaptureDate -Path $file.Path -ExifToolPath $config.Tools.ExifTool -DateConfig $config.Dates
            if ($videoInfo.IsHdr) {
                $summary.Hdr++
            } else {
                $summary.Sdr++
            }

            switch ([string]$captureDateResult.Source) {
                'Metadata' { $summary.CaptureDateMetadata++ }
                'FileName' { $summary.CaptureDateFileName++ }
                default { $summary.CaptureDateMissing++ }
            }

            Write-CaptureDateStatus -FileName $file.RelativePath -CaptureDateResult $captureDateResult

            foreach ($captureWarning in @($captureDateResult.Warnings)) {
                Write-VideoArchiveStatus -Message ("Warning: {0} | {1}" -f $file.RelativePath, $captureWarning) -Level Warn
            }

            $outputExtension = Get-ArchiveOutputExtension -SourcePath $file.Path
            $relativeOutputPath = [System.IO.Path]::ChangeExtension($file.RelativePath, $outputExtension)
            $outputRoot = if ($videoInfo.IsHdr) { $outputRoots.HDR } else { $outputRoots.SDR }
            $finalOutputFile = Join-Path -Path $outputRoot -ChildPath $relativeOutputPath

            if (-not $captureDateResult.Success -and [bool]$config.Dates.strictDateMode) {
                $summary.Skipped++
                $reason = 'Capture date could not be determined in strict date mode.'
                Write-VideoArchiveStatus -Message ("[{0}/{1}] {2} -> Skip ({3})" -f ($index + 1), $files.Count, $file.RelativePath, $reason) -Level Warn
                Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                    -SourcePath $file.Path `
                    -OutputPath $finalOutputFile `
                    -Action 'Skip' `
                    -Reason $reason `
                    -OutputGroup $(if ($videoInfo.IsHdr) { 'HDR' } else { 'SDR' }) `
                    -Codec $videoInfo.Codec `
                    -BitrateMbps $videoInfo.BitrateMbps `
                    -IsHdr $videoInfo.IsHdr `
                    -HdrType $videoInfo.HdrType `
                    -SourceSizeMb $videoInfo.SourceSizeMb `
                    -OutputSizeMb $null `
                    -SavingsPercent $null `
                    -ValidationPassed $false `
                    -ValidationWarnings $null `
                    -ValidationErrors $reason `
                    -Duration $null `
                    -DryRunFlag $false `
                    -HdrTypeSource $videoInfo.HdrType `
                    -HdrTypeOutput $null `
                    -SourceWidth $videoInfo.Width `
                    -SourceHeight $videoInfo.Height `
                    -OutputWidth $null `
                    -OutputHeight $null `
                    -SourceTransfer $videoInfo.Transfer `
                    -OutputTransfer $null `
                    -SourcePrimaries $videoInfo.Primaries `
                    -OutputPrimaries $null `
                    -SourceBitDepth $videoInfo.BitDepth `
                    -OutputBitDepth $null `
                    -CaptureDate $null `
                    -CaptureDateSource $captureDateResult.Source `
                    -CaptureDatePattern $captureDateResult.Pattern `
                    -CaptureDateRecognized $false `
                    -CaptureDateWarnings ($captureDateResult.Warnings -join '; ') `
                    -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                    -DateValidationSuccess $false)
                $completedCount++
                continue
            }

            $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile $finalOutputFile -SmartSkip $config.SmartSkip -PresetName $config.PresetName -Force:$Force -NoSmartSkip:$NoSmartSkip
            Write-VideoArchiveStatus -Message ("[{0}/{1}] {2} -> {3} ({4})" -f ($index + 1), $files.Count, $file.RelativePath, $decision.Action, $decision.Reason)

            if ($decision.Action -eq 'Skip') {
                $summary.Skipped++
                Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                    -SourcePath $file.Path `
                    -OutputPath $finalOutputFile `
                    -Action 'Skip' `
                    -Reason $decision.Reason `
                    -OutputGroup $decision.OutputGroup `
                    -Codec $videoInfo.Codec `
                    -BitrateMbps $videoInfo.BitrateMbps `
                    -IsHdr $videoInfo.IsHdr `
                    -HdrType $videoInfo.HdrType `
                    -SourceSizeMb $videoInfo.SourceSizeMb `
                    -OutputSizeMb $null `
                    -SavingsPercent $null `
                    -ValidationPassed $false `
                    -ValidationWarnings $null `
                    -ValidationErrors $null `
                    -Duration $null `
                    -DryRunFlag $false `
                    -HdrTypeSource $videoInfo.HdrType `
                    -HdrTypeOutput $null `
                    -SourceWidth $videoInfo.Width `
                    -SourceHeight $videoInfo.Height `
                    -OutputWidth $null `
                    -OutputHeight $null `
                    -SourceTransfer $videoInfo.Transfer `
                    -OutputTransfer $null `
                    -SourcePrimaries $videoInfo.Primaries `
                    -OutputPrimaries $null `
                    -SourceBitDepth $videoInfo.BitDepth `
                    -OutputBitDepth $null `
                    -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }) `
                    -CaptureDateSource $captureDateResult.Source `
                    -CaptureDatePattern $captureDateResult.Pattern `
                    -CaptureDateRecognized $captureDateResult.Success `
                    -CaptureDateWarnings ($captureDateResult.Warnings -join '; ') `
                    -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                    -DateValidationSuccess $captureDateResult.Success)
                $completedCount++
                continue
            }

            if ($DryRun) {
                $summary.DryRun++
                Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                    -SourcePath $file.Path `
                    -OutputPath $finalOutputFile `
                    -Action 'DryRun' `
                    -Reason $decision.Reason `
                    -OutputGroup $decision.OutputGroup `
                    -Codec $videoInfo.Codec `
                    -BitrateMbps $videoInfo.BitrateMbps `
                    -IsHdr $videoInfo.IsHdr `
                    -HdrType $videoInfo.HdrType `
                    -SourceSizeMb $videoInfo.SourceSizeMb `
                    -OutputSizeMb $null `
                    -SavingsPercent $null `
                    -ValidationPassed $false `
                    -ValidationWarnings $null `
                    -ValidationErrors $null `
                    -Duration $null `
                    -DryRunFlag $true `
                    -HdrTypeSource $videoInfo.HdrType `
                    -HdrTypeOutput $null `
                    -SourceWidth $videoInfo.Width `
                    -SourceHeight $videoInfo.Height `
                    -OutputWidth $null `
                    -OutputHeight $null `
                    -SourceTransfer $videoInfo.Transfer `
                    -OutputTransfer $null `
                    -SourcePrimaries $videoInfo.Primaries `
                    -OutputPrimaries $null `
                    -SourceBitDepth $videoInfo.BitDepth `
                    -OutputBitDepth $null `
                    -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }) `
                    -CaptureDateSource $captureDateResult.Source `
                    -CaptureDatePattern $captureDateResult.Pattern `
                    -CaptureDateRecognized $captureDateResult.Success `
                    -CaptureDateWarnings ($captureDateResult.Warnings -join '; ') `
                    -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                    -DateValidationSuccess $captureDateResult.Success)
                $completedCount++
                continue
            }

            $tempOutputFile = Get-TempOutputPath -TempRoot $tempRoot -RelativePath $relativeOutputPath
            $job = New-EncodeJob -InputFile $file.Path -OutputFile $tempOutputFile -VideoInfo $videoInfo -NvEncPath $config.Tools.NvEnc -Preset $config.Preset
            $encodeResult = Invoke-EncodeJob -Job $job -ProgressCallback { param($telemetry) Update-EncodeTelemetry -Telemetry $telemetry }

            if (-not $encodeResult.Success) {
                $summary.Failed++
                Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                    -SourcePath $file.Path `
                    -OutputPath $finalOutputFile `
                    -Action 'Failed' `
                    -Reason ("NVEncC failed with exit code {0}. {1}" -f $encodeResult.ExitCode, $encodeResult.Log) `
                    -OutputGroup $decision.OutputGroup `
                    -Codec $videoInfo.Codec `
                    -BitrateMbps $videoInfo.BitrateMbps `
                    -IsHdr $videoInfo.IsHdr `
                    -HdrType $videoInfo.HdrType `
                    -SourceSizeMb $videoInfo.SourceSizeMb `
                    -OutputSizeMb $null `
                    -SavingsPercent $null `
                    -ValidationPassed $false `
                    -ValidationWarnings $null `
                    -ValidationErrors $encodeResult.Log `
                    -Duration $encodeResult.Duration.ToString() `
                    -DryRunFlag $false `
                    -HdrTypeSource $videoInfo.HdrType `
                    -HdrTypeOutput $null `
                    -SourceWidth $videoInfo.Width `
                    -SourceHeight $videoInfo.Height `
                    -OutputWidth $null `
                    -OutputHeight $null `
                    -SourceTransfer $videoInfo.Transfer `
                    -OutputTransfer $null `
                    -SourcePrimaries $videoInfo.Primaries `
                    -OutputPrimaries $null `
                    -SourceBitDepth $videoInfo.BitDepth `
                    -OutputBitDepth $null `
                    -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }) `
                    -CaptureDateSource $captureDateResult.Source `
                    -CaptureDatePattern $captureDateResult.Pattern `
                    -CaptureDateRecognized $captureDateResult.Success `
                    -CaptureDateWarnings ($captureDateResult.Warnings -join '; ') `
                    -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                    -DateValidationSuccess $false)
                $completedCount++
                continue
            }

            $finalDirectory = Split-Path -Path $finalOutputFile -Parent
            if (-not (Test-Path -LiteralPath $finalDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $finalDirectory -Force | Out-Null
            }

            Move-Item -LiteralPath $tempOutputFile -Destination $finalOutputFile -Force
            Copy-VideoMetadata -SourceFile $file.Path -DestinationFile $finalOutputFile -ExifToolPath $config.Tools.ExifTool -PreserveWindowsTimestamps:([bool]$config.Metadata.preserveWindowsTimestamps) | Out-Null
            if ($captureDateResult.Success -and ($captureDateResult.Source -eq 'FileName' -or [bool]$config.Dates.setAllCommonDateTags)) {
                Set-VideoCaptureDate -Path $finalOutputFile -CaptureDate $captureDateResult.DateTime -Source $captureDateResult.Source -ExifToolPath $config.Tools.ExifTool -SetAllCommonDateTags:([bool]$config.Dates.setAllCommonDateTags) | Out-Null
            }

            $outputInfo = Get-VideoInfo -Path $finalOutputFile -MediaInfoPath $config.Tools.MediaInfo
            $outputMetadata = Get-VideoMetadataSnapshot -Path $finalOutputFile -ExifToolPath $config.Tools.ExifTool
            $validation = Test-EncodedVideo -SourceFile $file.Path -SourceInfo $videoInfo -OutputInfo $outputInfo -OutputFile $finalOutputFile -ValidateTimestamps:([bool]$config.Metadata.preserveWindowsTimestamps) -SourceMetadata $sourceMetadata -OutputMetadata $outputMetadata -CaptureDateResult $captureDateResult -StrictDateMode:([bool]$config.Dates.strictDateMode)

            if (-not $validation.Success) {
                $summary.Failed++
                Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                    -SourcePath $file.Path `
                    -OutputPath $finalOutputFile `
                    -Action 'Failed' `
                    -Reason ($validation.Errors -join '; ') `
                    -OutputGroup $decision.OutputGroup `
                    -Codec $videoInfo.Codec `
                    -BitrateMbps $videoInfo.BitrateMbps `
                    -IsHdr $videoInfo.IsHdr `
                    -HdrType $videoInfo.HdrType `
                    -SourceSizeMb $videoInfo.SourceSizeMb `
                    -OutputSizeMb $null `
                    -SavingsPercent $null `
                    -ValidationPassed $false `
                    -ValidationWarnings ($validation.Warnings -join '; ') `
                    -ValidationErrors ($validation.Errors -join '; ') `
                    -Duration $encodeResult.Duration.ToString() `
                    -DryRunFlag $false `
                    -HdrTypeSource $videoInfo.HdrType `
                    -HdrTypeOutput $outputInfo.HdrType `
                    -SourceWidth $videoInfo.Width `
                    -SourceHeight $videoInfo.Height `
                    -OutputWidth $outputInfo.Width `
                    -OutputHeight $outputInfo.Height `
                    -SourceTransfer $videoInfo.Transfer `
                    -OutputTransfer $outputInfo.Transfer `
                    -SourcePrimaries $videoInfo.Primaries `
                    -OutputPrimaries $outputInfo.Primaries `
                    -SourceBitDepth $videoInfo.BitDepth `
                    -OutputBitDepth $outputInfo.BitDepth `
                    -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }) `
                    -CaptureDateSource $captureDateResult.Source `
                    -CaptureDatePattern $captureDateResult.Pattern `
                    -CaptureDateRecognized $captureDateResult.Success `
                    -CaptureDateWarnings (($captureDateResult.Warnings + $validation.Warnings) -join '; ') `
                    -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                    -DateValidationSuccess $false)
                $completedCount++
                continue
            }

            $sourceSizeMb = [math]::Round((Get-Item -LiteralPath $file.Path).Length / 1MB, 2)
            $outputSizeMb = [math]::Round((Get-Item -LiteralPath $finalOutputFile).Length / 1MB, 2)
            $savingsPercent = if ($sourceSizeMb -gt 0) {
                [math]::Round((($sourceSizeMb - $outputSizeMb) / $sourceSizeMb) * 100, 2)
            } else {
                0
            }

            $smartSkipActive = (-not $Force) -and (-not $NoSmartSkip) -and [bool]$config.SmartSkip.enabled
            if ($smartSkipActive -and $savingsPercent -lt [double]$config.SmartSkip.deleteOutputIfSavingsBelowPercent) {
                Remove-IfExists -Path $finalOutputFile
                $summary.Skipped++
                Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                    -SourcePath $file.Path `
                    -OutputPath $finalOutputFile `
                    -Action 'Skip' `
                    -Reason ("Savings {0}% below threshold {1}%" -f $savingsPercent, $config.SmartSkip.deleteOutputIfSavingsBelowPercent) `
                    -OutputGroup $decision.OutputGroup `
                    -Codec $videoInfo.Codec `
                    -BitrateMbps $videoInfo.BitrateMbps `
                    -IsHdr $videoInfo.IsHdr `
                    -HdrType $videoInfo.HdrType `
                    -SourceSizeMb $sourceSizeMb `
                    -OutputSizeMb $outputSizeMb `
                    -SavingsPercent $savingsPercent `
                    -ValidationPassed $true `
                    -ValidationWarnings ($validation.Warnings -join '; ') `
                    -ValidationErrors $null `
                    -Duration $encodeResult.Duration.ToString() `
                    -DryRunFlag $false `
                    -HdrTypeSource $videoInfo.HdrType `
                    -HdrTypeOutput $outputInfo.HdrType `
                    -SourceWidth $videoInfo.Width `
                    -SourceHeight $videoInfo.Height `
                    -OutputWidth $outputInfo.Width `
                    -OutputHeight $outputInfo.Height `
                    -SourceTransfer $videoInfo.Transfer `
                    -OutputTransfer $outputInfo.Transfer `
                    -SourcePrimaries $videoInfo.Primaries `
                    -OutputPrimaries $outputInfo.Primaries `
                    -SourceBitDepth $videoInfo.BitDepth `
                    -OutputBitDepth $outputInfo.BitDepth `
                    -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }) `
                    -CaptureDateSource $captureDateResult.Source `
                    -CaptureDatePattern $captureDateResult.Pattern `
                    -CaptureDateRecognized $captureDateResult.Success `
                    -CaptureDateWarnings (($captureDateResult.Warnings + $validation.Warnings) -join '; ') `
                    -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                    -DateValidationSuccess $validation.Success)
                $completedCount++
                continue
            }

            $summary.Encoded++
            Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                -SourcePath $file.Path `
                -OutputPath $finalOutputFile `
                -Action 'Encoded' `
                -Reason $decision.Reason `
                -OutputGroup $decision.OutputGroup `
                -Codec $videoInfo.Codec `
                -BitrateMbps $videoInfo.BitrateMbps `
                -IsHdr $videoInfo.IsHdr `
                -HdrType $videoInfo.HdrType `
                -SourceSizeMb $sourceSizeMb `
                -OutputSizeMb $outputSizeMb `
                -SavingsPercent $savingsPercent `
                -ValidationPassed $true `
                -ValidationWarnings ($validation.Warnings -join '; ') `
                -ValidationErrors $null `
                -Duration $encodeResult.Duration.ToString() `
                -DryRunFlag $false `
                -HdrTypeSource $videoInfo.HdrType `
                -HdrTypeOutput $outputInfo.HdrType `
                -SourceWidth $videoInfo.Width `
                -SourceHeight $videoInfo.Height `
                -OutputWidth $outputInfo.Width `
                -OutputHeight $outputInfo.Height `
                -SourceTransfer $videoInfo.Transfer `
                -OutputTransfer $outputInfo.Transfer `
                -SourcePrimaries $videoInfo.Primaries `
                -OutputPrimaries $outputInfo.Primaries `
                -SourceBitDepth $videoInfo.BitDepth `
                -OutputBitDepth $outputInfo.BitDepth `
                -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null }) `
                -CaptureDateSource $captureDateResult.Source `
                -CaptureDatePattern $captureDateResult.Pattern `
                -CaptureDateRecognized $captureDateResult.Success `
                -CaptureDateWarnings (($captureDateResult.Warnings + $validation.Warnings) -join '; ') `
                -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                -DateValidationSuccess $validation.Success)
            $completedCount++
        } catch {
            $summary.Failed++
            $errorMessage = Get-ReadableErrorMessage -ErrorRecord $_
            Write-VideoArchiveStatus -Message ("Error: {0}" -f $errorMessage) -Level Error
            Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                -SourcePath $file.Path `
                -OutputPath $finalOutputFile `
                -Action 'Failed' `
                -Reason $errorMessage `
                -OutputGroup $null `
                -Codec $null `
                -BitrateMbps $null `
                -IsHdr $false `
                -HdrType $null `
                -SourceSizeMb $null `
                -OutputSizeMb $null `
                -SavingsPercent $null `
                -ValidationPassed $false `
                -ValidationWarnings $null `
                -ValidationErrors $errorMessage `
                -Duration $null `
                -DryRunFlag $false `
                -HdrTypeSource $null `
                -HdrTypeOutput $null `
                -SourceWidth $null `
                -SourceHeight $null `
                -OutputWidth $null `
                -OutputHeight $null `
                -SourceTransfer $null `
                -OutputTransfer $null `
                -SourcePrimaries $null `
                -OutputPrimaries $null `
                -SourceBitDepth $null `
                -OutputBitDepth $null)
            Remove-IfExists -Path $tempOutputFile
            $completedCount++
        }
    }

    Complete-VideoArchiveProgress
    Write-LogMessage -Logger $logger -Message ("Run finished. Encoded={0} Skipped={1} Failed={2} DryRun={3}" -f $summary.Encoded, $summary.Skipped, $summary.Failed, $summary.DryRun)
    Show-VideoArchiveSummary -Summary $summary
} finally {
    if ($null -ne $tempRoot -and (Test-Path -LiteralPath $tempRoot -PathType Container)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
