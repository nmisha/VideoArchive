param(
    [string]$InputPath,
    [string]$Preset,
    [switch]$Force,
    [switch]$NoSmartSkip,
    [switch]$DryRun
)

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
        [string]$Duration,
        [bool]$DryRunFlag
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
        ValidationPassed = $ValidationPassed
        Duration = $Duration
        DryRun = $DryRunFlag
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
    }

    $runStart = Get-Date

    for ($index = 0; $index -lt $files.Count; $index++) {
        $file = $files[$index]
        Update-VideoArchiveProgress -Current ($index + 1) -Total $files.Count -CurrentFile $file.RelativePath -StartTime $runStart

        $tempOutputFile = $null
        $finalOutputFile = $null

        try {
            $videoInfo = Get-VideoInfo -Path $file.Path -MediaInfoPath $config.Tools.MediaInfo
            if ($videoInfo.IsHdr) {
                $summary.Hdr++
            } else {
                $summary.Sdr++
            }

            $outputExtension = Get-ArchiveOutputExtension -SourcePath $file.Path
            $relativeOutputPath = [System.IO.Path]::ChangeExtension($file.RelativePath, $outputExtension)
            $outputRoot = if ($videoInfo.IsHdr) { $outputRoots.HDR } else { $outputRoots.SDR }
            $finalOutputFile = Join-Path -Path $outputRoot -ChildPath $relativeOutputPath

            $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile $finalOutputFile -SmartSkip $config.SmartSkip -Force:$Force -NoSmartSkip:$NoSmartSkip
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
                    -Duration $null `
                    -DryRunFlag $false)
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
                    -Duration $null `
                    -DryRunFlag $true)
                continue
            }

            $tempOutputFile = Get-TempOutputPath -TempRoot $tempRoot -RelativePath $relativeOutputPath
            $job = New-EncodeJob -InputFile $file.Path -OutputFile $tempOutputFile -VideoInfo $videoInfo -NvEncPath $config.Tools.NvEnc -Preset $config.Preset
            $encodeResult = Invoke-EncodeJob -Job $job

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
                    -Duration $encodeResult.Duration.ToString() `
                    -DryRunFlag $false)
                continue
            }

            $finalDirectory = Split-Path -Path $finalOutputFile -Parent
            if (-not (Test-Path -LiteralPath $finalDirectory -PathType Container)) {
                New-Item -ItemType Directory -Path $finalDirectory -Force | Out-Null
            }

            Move-Item -LiteralPath $tempOutputFile -Destination $finalOutputFile -Force
            Copy-VideoMetadata -SourceFile $file.Path -DestinationFile $finalOutputFile -ExifToolPath $config.Tools.ExifTool -PreserveWindowsTimestamps:([bool]$config.Metadata.preserveWindowsTimestamps) | Out-Null

            $outputInfo = Get-VideoInfo -Path $finalOutputFile -MediaInfoPath $config.Tools.MediaInfo
            $validation = Test-EncodedVideo -SourceFile $file.Path -SourceInfo $videoInfo -OutputInfo $outputInfo -OutputFile $finalOutputFile -ValidateTimestamps:([bool]$config.Metadata.preserveWindowsTimestamps)

            if (-not $validation.Success) {
                $summary.Failed++
                Remove-IfExists -Path $finalOutputFile
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
                    -Duration $encodeResult.Duration.ToString() `
                    -DryRunFlag $false)
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
                    -Duration $encodeResult.Duration.ToString() `
                    -DryRunFlag $false)
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
                -Duration $encodeResult.Duration.ToString() `
                -DryRunFlag $false)
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
                -Duration $null `
                -DryRunFlag $false)
            Remove-IfExists -Path $tempOutputFile
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
