param(
    [string]$InputPath,
    [string]$Preset,
    [switch]$Force,
    [switch]$NoSmartSkip,
    [switch]$DryRun,
    [switch]$Resume,
    [string]$ResumeFrom,
    [ValidateSet('failed', 'unfinished', 'all')]
    [string]$ResumeMode = 'unfinished'
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
    'Resume.psm1',
    'Metadata.psm1',
    'Logger.psm1',
    'ConsoleUI.psm1',
    'Validator.psm1'
)

foreach ($module in $requiredModules) {
    Import-Module (Join-Path -Path $moduleRoot -ChildPath $module) -Force
}

$script:VideoArchivePresetName = $null

function Get-ResultClassForAction {
    param([string]$Action)

    switch ($Action) {
        'Encoded' { return 'Success' }
        'Failed' { return 'Failed' }
        'DryRun' { return 'Planned' }
        'Skip' { return 'Skipped' }
        default { return 'Unknown' }
    }
}

function Get-SkipCategoryFromContext {
    param(
        [string]$Action,
        [string]$Reason
    )

    if ($Action -ne 'Skip' -or [string]::IsNullOrWhiteSpace($Reason)) {
        return $null
    }

    if ($Reason -match 'Output already exists') { return 'ExistingOutput' }
    if ($Reason -match 'Savings .* below threshold') { return 'SavingsBelowThreshold' }
    if ($Reason -match 'below threshold') { return 'SmartSkip' }
    if ($Reason -match 'smaller than') { return 'SmartSkip' }
    if ($Reason -match 'AV1 source skipped') { return 'SmartSkip' }
    if ($Reason -match 'strict date mode') { return 'StrictDateMode' }
    if ($Reason -match 'Already completed in resume log') { return 'ResumeCompleted' }
    if ($Reason -match 'No failed resume record') { return 'ResumeNoFailedRecord' }
    if ($Reason -match "not 'Failed'") { return 'ResumeNotFailed' }

    return 'GeneralSkip'
}

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
        [bool]$DateValidationSuccess = $false,
        [string]$ResultClass,
        [string]$SkipCategory,
        [string]$PresetName,
        [Nullable[long]]$SourceFileSizeBytes,
        [string]$SourceLastWriteTimeUtc,
        [string]$SourceCreationTimeUtc,
        [Nullable[long]]$OutputFileSizeBytes
    )

    if ([string]::IsNullOrWhiteSpace($ResultClass)) {
        $ResultClass = Get-ResultClassForAction -Action $Action
    }

    if ([string]::IsNullOrWhiteSpace($SkipCategory)) {
        $SkipCategory = Get-SkipCategoryFromContext -Action $Action -Reason $Reason
    }

    if ([string]::IsNullOrWhiteSpace($PresetName)) {
        $PresetName = $script:VideoArchivePresetName
    }

    if (($null -eq $SourceFileSizeBytes -or [string]::IsNullOrWhiteSpace($SourceLastWriteTimeUtc) -or [string]::IsNullOrWhiteSpace($SourceCreationTimeUtc)) -and -not [string]::IsNullOrWhiteSpace($SourcePath) -and (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        $sourceItem = Get-Item -LiteralPath $SourcePath
        if ($null -eq $SourceFileSizeBytes) { $SourceFileSizeBytes = $sourceItem.Length }
        if ([string]::IsNullOrWhiteSpace($SourceLastWriteTimeUtc)) { $SourceLastWriteTimeUtc = $sourceItem.LastWriteTimeUtc.ToString('o') }
        if ([string]::IsNullOrWhiteSpace($SourceCreationTimeUtc)) { $SourceCreationTimeUtc = $sourceItem.CreationTimeUtc.ToString('o') }
    }

    if ($null -eq $OutputFileSizeBytes -and -not [string]::IsNullOrWhiteSpace($OutputPath) -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        $OutputFileSizeBytes = (Get-Item -LiteralPath $OutputPath).Length
    }

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
        ResultClass = $ResultClass
        SkipCategory = $SkipCategory
        PresetName = $PresetName
        SourceFileSizeBytes = $SourceFileSizeBytes
        SourceLastWriteTimeUtc = $SourceLastWriteTimeUtc
        SourceCreationTimeUtc = $SourceCreationTimeUtc
        OutputFileSizeBytes = $OutputFileSizeBytes
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
        [string]$FinalOutputPath,

        [Parameter(Mandatory)]
        [string]$RunId
    )

    $directory = Split-Path -Path $FinalOutputPath -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FinalOutputPath)
    $extension = [System.IO.Path]::GetExtension($FinalOutputPath)
    $tempName = '{0}_va_tmp_{1}{2}' -f $baseName, $RunId, $extension
    return Join-Path -Path $directory -ChildPath $tempName
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
    $script:VideoArchivePresetName = $config.PresetName
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
    $resumeLogPath = $null
    $resumePlan = $null
    if ($Resume -or -not [string]::IsNullOrWhiteSpace($ResumeFrom)) {
        $resumeLogPath = Resolve-ResumeLogPath -LogRoot $config.Output.LogsFolder -ResumeFrom $ResumeFrom
        $resumePlan = Get-ResumePlan -Files $files -ResumeLogPath $resumeLogPath -ResumeMode $ResumeMode -PresetName $config.PresetName
        $files = @($resumePlan.ScheduledFiles)
    }

    $logger = Initialize-VideoArchiveLogger -LogRoot $config.Output.LogsFolder
    Show-VideoArchiveBanner -Config $config
    Write-VideoArchiveStatus -Message "Input : $resolvedInputPath"
    Write-VideoArchiveStatus -Message "Files : $($files.Count)"
    Write-VideoArchiveStatus -Message "Logs  : $($logger.TxtPath)"

    if ($null -ne $resumePlan) {
        Write-VideoArchiveStatus -Message "Resume: $resumeLogPath"
        Write-VideoArchiveStatus -Message "Resume Mode: $ResumeMode"
        Write-VideoArchiveStatus -Message "Resume Skipped: $($resumePlan.SkippedFiles.Count)"
    }

    Write-LogMessage -Logger $logger -Message "Run started. Input=$resolvedInputPath Preset=$($config.PresetName) Force=$Force NoSmartSkip=$NoSmartSkip DryRun=$DryRun Resume=$Resume ResumeFrom=$resumeLogPath ResumeMode=$ResumeMode"

    if ($files.Count -eq 0) {
        $message = if ($null -ne $resumePlan) { 'No files scheduled after resume filtering.' } else { 'No supported video files found.' }
        Write-VideoArchiveStatus -Message $message -Level Warn
        Write-LogMessage -Logger $logger -Message $message
        exit 0
    }

    $summary = [pscustomobject]@{
        Encoded = 0
        Skipped = 0
        Failed = 0
        DryRun = 0
        ResumeSkipped = 0
        Hdr = 0
        Sdr = 0
        CaptureDateMetadata = 0
        CaptureDateFileName = 0
        CaptureDateMissing = 0
        TotalSourceMb = 0.0
        TotalOutputMb = 0.0
        TotalSavingsPercent = 0.0
        AverageEncodedSavingsPercent = 0.0
        FilesPerMinute = 0.0
        TotalElapsed = [TimeSpan]::Zero
    }

    if ($null -ne $resumePlan) {
        foreach ($resumeSkip in @($resumePlan.SkippedFiles)) {
            $summary.Skipped++
            $summary.ResumeSkipped++
            Write-DecisionStatus -Message ("[resume] {0} -> Skip ({1})" -f $resumeSkip.File.RelativePath, $resumeSkip.Reason) -Action Resume
            Write-LogRecord -Logger $logger -Record (New-VideoArchiveRecord `
                -SourcePath $resumeSkip.File.Path `
                -OutputPath $resumeSkip.OutputPath `
                -Action 'Skip' `
                -Reason $resumeSkip.Reason `
                -DryRunFlag $false `
                -CaptureDateRecognized $false `
                -StrictDateMode ([bool]$config.Dates.strictDateMode) `
                -DateValidationSuccess $false `
                -SkipCategory $resumeSkip.SkipCategory `
                -ResultClass 'Skipped' `
                -SourceFileSizeBytes $resumeSkip.File.SizeBytes `
                -SourceLastWriteTimeUtc $resumeSkip.File.LastWriteTimeUtc.ToString('o') `
                -SourceCreationTimeUtc $resumeSkip.File.CreationTimeUtc.ToString('o'))
        }
    }

    $totalSourceBytes = (@($files) | Measure-Object -Property SizeBytes -Sum).Sum
    $processedSourceBytes = 0L
    $encodedSourceBytes = 0L
    $encodedOutputBytes = 0L
    $encodedSavingsSum = 0.0
    $runStart = Get-Date
    $completedCount = 0

    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        Reset-EncodeTelemetryState
        Update-VideoArchiveProgress -Current ($index + 1) -Completed $completedCount -Total $files.Count -CurrentFile $file.RelativePath -StartTime $runStart -ProcessedSourceMb ([math]::Round($processedSourceBytes / 1MB, 2)) -TotalSourceMb ([math]::Round($totalSourceBytes / 1MB, 2)) -Encoded $summary.Encoded -Skipped $summary.Skipped -Failed $summary.Failed -DryRun $summary.DryRun -ResumeSkipped $summary.ResumeSkipped

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
                Write-DecisionStatus -Message ("[{0}/{1}] {2} -> Skip ({3})" -f ($index + 1), $files.Count, $file.RelativePath, $reason) -Action Skip
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
                $processedSourceBytes += [long]$file.SizeBytes
                continue
            }

            $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile $finalOutputFile -SmartSkip $config.SmartSkip -PresetName $config.PresetName -Force:$Force -NoSmartSkip:$NoSmartSkip
            Write-DecisionStatus -Message ("[{0}/{1}] {2} -> {3} ({4})" -f ($index + 1), $files.Count, $file.RelativePath, $decision.Action, $decision.Reason) -Action $decision.Action

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
                $processedSourceBytes += [long]$file.SizeBytes
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
                $processedSourceBytes += [long]$file.SizeBytes
                continue
            }

            $tempOutputFile = Get-TempOutputPath -FinalOutputPath $finalOutputFile -RunId $logger.RunId
            $job = New-EncodeJob -InputFile $file.Path -OutputFile $tempOutputFile -VideoInfo $videoInfo -NvEncPath $config.Tools.NvEnc -Preset $config.Preset
            $encodeResult = Invoke-EncodeJob -Job $job -ProgressCallback { param($telemetry) Update-EncodeTelemetry -Telemetry $telemetry -Completed $completedCount -Total $files.Count -StartTime $runStart -Encoded $summary.Encoded -Skipped $summary.Skipped -Failed $summary.Failed -DryRun $summary.DryRun -ResumeSkipped $summary.ResumeSkipped }
            $tempOutputFile = $encodeResult.OutputFile

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
                $processedSourceBytes += [long]$file.SizeBytes
                continue
            }

            $finalDirectory = Split-Path -Path $finalOutputFile -Parent
            if (-not (Test-Path -LiteralPath $finalDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $finalDirectory -Force | Out-Null
            }

            Move-Item -LiteralPath $tempOutputFile -Destination $finalOutputFile -Force
            Copy-VideoMetadata -SourceFile $file.Path -DestinationFile $finalOutputFile -ExifToolPath $config.Tools.ExifTool -PreserveWindowsTimestamps:([bool]$config.Metadata.preserveWindowsTimestamps) -FileTimestampMode ([string]$config.Metadata.fileTimestampMode) -CaptureDate $(if ($captureDateResult.Success) { $captureDateResult.DateTime } else { $null }) -CaptureDateSource ([string]$captureDateResult.Source) -CaptureDateOffset ([string]$config.Dates.defaultTimezoneOffset) | Out-Null
            if ($captureDateResult.Success -and $captureDateResult.Source -eq 'FileName') {
                Set-VideoCaptureDate -Path $finalOutputFile -CaptureDate $captureDateResult.DateTime -Source $captureDateResult.Source -ExifToolPath $config.Tools.ExifTool -SetAllCommonDateTags:([bool]$config.Dates.setAllCommonDateTags) | Out-Null
            }

            $outputInfo = Get-VideoInfo -Path $finalOutputFile -MediaInfoPath $config.Tools.MediaInfo
            $outputMetadata = Get-VideoMetadataSnapshot -Path $finalOutputFile -ExifToolPath $config.Tools.ExifTool
            $validation = Test-EncodedVideo -SourceFile $file.Path -SourceInfo $videoInfo -OutputInfo $outputInfo -OutputFile $finalOutputFile -ValidateTimestamps:([bool]$config.Metadata.preserveWindowsTimestamps) -SourceMetadata $sourceMetadata -OutputMetadata $outputMetadata -CaptureDateResult $captureDateResult -StrictDateMode:([bool]$config.Dates.strictDateMode) -FileTimestampMode ([string]$config.Metadata.fileTimestampMode) -FileTimestampOffset ([string]$config.Dates.defaultTimezoneOffset)

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
                $processedSourceBytes += [long]$file.SizeBytes
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
                Write-FileResultStatus -FileName $file.RelativePath -Action 'Discarded' -SourceSizeMb $sourceSizeMb -OutputSizeMb $outputSizeMb -SavingsPercent $savingsPercent -Duration $encodeResult.Duration
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
                $processedSourceBytes += [long]$file.SizeBytes
                continue
            }

            $summary.Encoded++
            $processedSourceBytes += [long]$file.SizeBytes
            $encodedSourceBytes += (Get-Item -LiteralPath $file.Path).Length
            $encodedOutputBytes += (Get-Item -LiteralPath $finalOutputFile).Length
            $encodedSavingsSum += $savingsPercent
            Write-FileResultStatus -FileName $file.RelativePath -Action 'Encoded' -SourceSizeMb $sourceSizeMb -OutputSizeMb $outputSizeMb -SavingsPercent $savingsPercent -Duration $encodeResult.Duration
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
            $processedSourceBytes += [long]$file.SizeBytes
        }
    }

    $summary.TotalElapsed = (Get-Date) - $runStart
    $summary.TotalSourceMb = [math]::Round($totalSourceBytes / 1MB, 2)
    $summary.TotalOutputMb = [math]::Round($encodedOutputBytes / 1MB, 2)
    if ($encodedSourceBytes -gt 0) {
        $summary.TotalSavingsPercent = [math]::Round((($encodedSourceBytes - $encodedOutputBytes) / $encodedSourceBytes) * 100, 2)
    }
    if ($summary.Encoded -gt 0) {
        $summary.AverageEncodedSavingsPercent = [math]::Round(($encodedSavingsSum / $summary.Encoded), 2)
    }
    if ($summary.TotalElapsed.TotalMinutes -gt 0) {
        $summary.FilesPerMinute = [math]::Round(($completedCount / $summary.TotalElapsed.TotalMinutes), 2)
    }

    Write-LogMessage -Logger $logger -Message ("Run finished. Encoded={0} Skipped={1} ResumeSkipped={2} Failed={3} DryRun={4}" -f $summary.Encoded, $summary.Skipped, $summary.ResumeSkipped, $summary.Failed, $summary.DryRun)
    Show-VideoArchiveSummary -Summary $summary
} finally {
    Complete-VideoArchiveProgress
}
