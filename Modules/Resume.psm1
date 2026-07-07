Set-StrictMode -Version Latest

function Get-ResumeValidationSuccess {
    param(
        [Parameter(Mandatory)]
        [psobject]$Record
    )

    foreach ($name in @('ValidationSuccess', 'ValidationPassed')) {
        $property = $Record.PSObject.Properties[$name]
        if ($null -ne $property) {
            return [bool]$property.Value
        }
    }

    return ($Record.Action -eq 'Encoded')
}

function ConvertTo-NullableUtcDateTime {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    try {
        return ([datetime]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()
    } catch {
        return $null
    }
}

function Resolve-ResumeLogPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot,

        [string]$ResumeFrom
    )

    if (-not [string]::IsNullOrWhiteSpace($ResumeFrom)) {
        $resolvedPath = [System.IO.Path]::GetFullPath($ResumeFrom)
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "Resume log not found: $resolvedPath"
        }

        return $resolvedPath
    }

    if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
        throw "Resume log folder not found: $LogRoot"
    }

    $latest = Get-ChildItem -LiteralPath $LogRoot -Filter 'VideoArchive_*.jsonl' -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "No resume JSONL logs found in '$LogRoot'."
    }

    return $latest.FullName
}

function Read-ResumeRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Resume log not found: $Path"
    }

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding utf8)) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $record = $line | ConvertFrom-Json
            if ($null -ne $record -and -not [string]::IsNullOrWhiteSpace([string]$record.SourcePath)) {
                $records.Add($record)
            }
        } catch {
        }
    }

    return $records.ToArray()
}

function Test-ResumeFingerprintMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$FileRecord,

        [Parameter(Mandatory)]
        [psobject]$HistoryRecord
    )

    $sizeProperty = $HistoryRecord.PSObject.Properties['SourceFileSizeBytes']
    if ($null -ne $sizeProperty -and $null -ne $sizeProperty.Value) {
        if ([long]$sizeProperty.Value -ne [long]$FileRecord.SizeBytes) {
            return $false
        }
    }

    $lastWriteUtc = ConvertTo-NullableUtcDateTime -Value $HistoryRecord.SourceLastWriteTimeUtc
    if ($null -ne $lastWriteUtc -and $lastWriteUtc -ne [datetime]$FileRecord.LastWriteTimeUtc) {
        return $false
    }

    $creationUtc = ConvertTo-NullableUtcDateTime -Value $HistoryRecord.SourceCreationTimeUtc
    if ($null -ne $creationUtc -and $creationUtc -ne [datetime]$FileRecord.CreationTimeUtc) {
        return $false
    }

    return $true
}

function Test-ResumeRecordCompleted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$FileRecord,

        [Parameter(Mandatory)]
        [psobject]$HistoryRecord,

        [string]$PresetName
    )

    if ([string]$HistoryRecord.Action -ne 'Encoded') {
        return $false
    }

    if (-not (Get-ResumeValidationSuccess -Record $HistoryRecord)) {
        return $false
    }

    if ([bool]$HistoryRecord.DryRun) {
        return $false
    }

    $historyPreset = [string]$HistoryRecord.PresetName
    if (-not [string]::IsNullOrWhiteSpace($historyPreset) -and -not [string]::IsNullOrWhiteSpace($PresetName) -and $historyPreset -ne $PresetName) {
        return $false
    }

    if (-not (Test-ResumeFingerprintMatch -FileRecord $FileRecord -HistoryRecord $HistoryRecord)) {
        return $false
    }

    $outputPath = [string]$HistoryRecord.OutputPath
    if ([string]::IsNullOrWhiteSpace($outputPath) -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
        return $false
    }

    $outputFile = Get-Item -LiteralPath $outputPath
    return ($outputFile.Length -gt 0)
}

function Get-ResumeDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$FileRecord,

        [psobject]$HistoryRecord,

        [ValidateSet('failed', 'unfinished', 'all')]
        [string]$ResumeMode = 'unfinished',

        [string]$PresetName
    )

    if ($ResumeMode -eq 'all') {
        return [pscustomobject]@{
            Process = $true
            Reason = 'ResumeMode=all'
            OutputPath = if ($null -ne $HistoryRecord) { [string]$HistoryRecord.OutputPath } else { $null }
            SkipCategory = $null
        }
    }

    if ($null -eq $HistoryRecord) {
        if ($ResumeMode -eq 'failed') {
            return [pscustomobject]@{
                Process = $false
                Reason = 'No failed resume record found.'
                OutputPath = $null
                SkipCategory = 'ResumeNoFailedRecord'
            }
        }

        return [pscustomobject]@{
            Process = $true
            Reason = 'No resume record found.'
            OutputPath = $null
            SkipCategory = $null
        }
    }

    $historyPreset = [string]$HistoryRecord.PresetName
    if (-not [string]::IsNullOrWhiteSpace($historyPreset) -and -not [string]::IsNullOrWhiteSpace($PresetName) -and $historyPreset -ne $PresetName) {
        return [pscustomobject]@{
            Process = $true
            Reason = "Resume record preset '$historyPreset' does not match current preset '$PresetName'."
            OutputPath = [string]$HistoryRecord.OutputPath
            SkipCategory = $null
        }
    }

    if (-not (Test-ResumeFingerprintMatch -FileRecord $FileRecord -HistoryRecord $HistoryRecord)) {
        return [pscustomobject]@{
            Process = $true
            Reason = 'Resume record fingerprint does not match current source file.'
            OutputPath = [string]$HistoryRecord.OutputPath
            SkipCategory = $null
        }
    }

    if ($ResumeMode -eq 'failed') {
        if ([string]$HistoryRecord.Action -eq 'Failed') {
            return [pscustomobject]@{
                Process = $true
                Reason = 'Resuming previously failed file.'
                OutputPath = [string]$HistoryRecord.OutputPath
                SkipCategory = $null
            }
        }

        return [pscustomobject]@{
            Process = $false
            Reason = "Last resume state is '$([string]$HistoryRecord.Action)', not 'Failed'."
            OutputPath = [string]$HistoryRecord.OutputPath
            SkipCategory = 'ResumeNotFailed'
        }
    }

    if (Test-ResumeRecordCompleted -FileRecord $FileRecord -HistoryRecord $HistoryRecord -PresetName $PresetName) {
        return [pscustomobject]@{
            Process = $false
            Reason = "Already completed in resume log: $([string]$HistoryRecord.OutputPath)"
            OutputPath = [string]$HistoryRecord.OutputPath
            SkipCategory = 'ResumeCompleted'
        }
    }

    return [pscustomobject]@{
        Process = $true
        Reason = "Resuming unfinished state '$([string]$HistoryRecord.Action)'."
        OutputPath = [string]$HistoryRecord.OutputPath
        SkipCategory = $null
    }
}

function Get-ResumePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject[]]$Files,

        [Parameter(Mandatory)]
        [string]$ResumeLogPath,

        [ValidateSet('failed', 'unfinished', 'all')]
        [string]$ResumeMode = 'unfinished',

        [string]$PresetName
    )

    $records = Read-ResumeRecords -Path $ResumeLogPath
    $index = @{}
    foreach ($record in $records) {
        $index[[string]$record.SourcePath] = $record
    }

    $scheduled = @()
    $skipped = @()

    foreach ($file in $Files) {
        $historyRecord = if ($index.ContainsKey($file.Path)) { $index[$file.Path] } else { $null }
        $decision = Get-ResumeDecision -FileRecord $file -HistoryRecord $historyRecord -ResumeMode $ResumeMode -PresetName $PresetName

        if ($decision.Process) {
            $scheduled += $file
            continue
        }

        $skipped += [pscustomobject]@{
            File = $file
            Reason = $decision.Reason
            OutputPath = $decision.OutputPath
            SkipCategory = $decision.SkipCategory
            HistoryRecord = $historyRecord
        }
    }

    return [pscustomobject]@{
        ResumeLogPath = $ResumeLogPath
        Records = @($records)
        ScheduledFiles = @($scheduled)
        SkippedFiles = @($skipped)
    }
}

Export-ModuleMember -Function Resolve-ResumeLogPath, Read-ResumeRecords, Test-ResumeRecordCompleted, Get-ResumeDecision, Get-ResumePlan
