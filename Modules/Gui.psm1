Set-StrictMode -Version Latest

function Read-VideoArchiveGuiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Write-VideoArchiveGuiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $Data
    )

    $json = $Data | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8
}

function Get-VideoArchivePresetDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $presetPath = Join-Path -Path $ProjectRoot -ChildPath 'presets.json'
    return Read-VideoArchiveGuiJson -Path $presetPath
}

function Save-VideoArchivePresetDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [psobject]$Presets
    )

    $presetPath = Join-Path -Path $ProjectRoot -ChildPath 'presets.json'
    Write-VideoArchiveGuiJson -Path $presetPath -Data $Presets
}

function Format-VideoArchiveQueueFlags {
    [CmdletBinding()]
    param(
        [switch]$Force,
        [switch]$NoSmartSkip,
        [switch]$DryRun,
        [switch]$Resume,

        [ValidateSet('failed', 'unfinished', 'all')]
        [string]$ResumeMode = 'unfinished'
    )

    $flags = New-Object System.Collections.Generic.List[string]
    if ($Force) { $flags.Add('Force') }
    if ($NoSmartSkip) { $flags.Add('NoSmartSkip') }
    if ($DryRun) { $flags.Add('DryRun') }
    if ($Resume) { $flags.Add("Resume:$ResumeMode") }

    if ($flags.Count -eq 0) {
        return 'Default'
    }

    return ($flags -join ', ')
}

function New-VideoArchiveQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [Parameter(Mandatory)]
        [string]$PresetName,

        [ValidateSet('auto', 'nvenc', 'qsv', 'amf', 'software')]
        [string]$EncoderBackend = 'auto',

        [ValidateSet('auto', 'hevc', 'av1')]
        [string]$OutputCodec = 'auto',

        [switch]$Force,
        [switch]$NoSmartSkip,
        [switch]$DryRun,
        [switch]$Resume,

        [ValidateSet('failed', 'unfinished', 'all')]
        [string]$ResumeMode = 'unfinished'
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($InputPath)

    [pscustomobject]@{
        Id = [guid]::NewGuid().ToString('N')
        InputPath = $resolvedPath
        PresetName = $PresetName
        EncoderBackend = $EncoderBackend
        OutputCodec = $OutputCodec
        Force = [bool]$Force
        NoSmartSkip = [bool]$NoSmartSkip
        DryRun = [bool]$DryRun
        Resume = [bool]$Resume
        ResumeMode = $ResumeMode
        Flags = Format-VideoArchiveQueueFlags -Force:$Force -NoSmartSkip:$NoSmartSkip -DryRun:$DryRun -Resume:$Resume -ResumeMode $ResumeMode
        Status = 'Queued'
        ProgressPercent = 0
        CurrentFile = $null
        LastMessage = 'Waiting'
        LogPath = $null
        CreatedAt = Get-Date
        StartedAt = $null
        FinishedAt = $null
        Encoded = 0
        Skipped = 0
        Failed = 0
        DryRunCount = 0
    }
}

function ConvertTo-VideoArchiveCliArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [Parameter(Mandatory)]
        [psobject]$QueueItem
    )

    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $ScriptPath
        '-InputPath'
        $QueueItem.InputPath
        '-Preset'
        $QueueItem.PresetName
        '-EncoderBackend'
        $QueueItem.EncoderBackend
        '-OutputCodec'
        $QueueItem.OutputCodec
    )

    if ($QueueItem.Force) { $arguments += '-Force' }
    if ($QueueItem.NoSmartSkip) { $arguments += '-NoSmartSkip' }
    if ($QueueItem.DryRun) { $arguments += '-DryRun' }
    if ($QueueItem.Resume) {
        $arguments += '-Resume'
        $arguments += '-ResumeMode'
        $arguments += $QueueItem.ResumeMode
    }

    return @($arguments)
}

function Get-VideoArchiveHistoryFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot
    )

    if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $LogRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.txt', '.jsonl', '.csv') } |
            Sort-Object LastWriteTime -Descending
    )
}

function Get-VideoArchiveFileTail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$LineCount = 200
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    return @(Get-Content -LiteralPath $Path -Tail $LineCount -ErrorAction SilentlyContinue)
}

function Find-VideoArchiveLogPathFromLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    foreach ($line in @($Lines)) {
        $match = [regex]::Match($line, '^\s*Logs\s*:\s*(?<path>.+?)\s*$')
        if ($match.Success) {
            return $match.Groups['path'].Value.Trim()
        }
    }

    return $null
}

function Get-VideoArchiveProgressSnapshotFromLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    $snapshot = [ordered]@{
        Percent = 0
        ProgressLine = $null
        CurrentFile = $null
        CaptureDateLine = $null
        TelemetryLine = $null
        LastErrorLine = $null
        Encoded = 0
        Skipped = 0
        Failed = 0
        DryRun = 0
        ResumeSkipped = 0
    }

    foreach ($line in @($Lines)) {
        if ($line -match '^Progress:\s+') {
            $snapshot.ProgressLine = $line
            $percentMatch = [regex]::Match($line, '\((?<percent>\d+)%\)')
            if ($percentMatch.Success) {
                $snapshot.Percent = [int]$percentMatch.Groups['percent'].Value
            }
        } elseif ($line -match '^Current\s*:\s*(?<file>.+)$') {
            $snapshot.CurrentFile = $matches['file'].Trim()
        } elseif ($line -match '^CaptureDate:') {
            $snapshot.CaptureDateLine = $line
        } elseif ($line -match '^Encoding:') {
            $snapshot.TelemetryLine = $line
        } elseif ($line -match '^Error:|^Validation failed:') {
            $snapshot.LastErrorLine = $line
        } elseif ($line -match '^Encoded\s*:\s*(?<count>\d+)$') {
            $snapshot.Encoded = [int]$matches['count']
        } elseif ($line -match '^Skipped\s*:\s*(?<count>\d+)$') {
            $snapshot.Skipped = [int]$matches['count']
        } elseif ($line -match '^ResSkip\s*:\s*(?<count>\d+)$') {
            $snapshot.ResumeSkipped = [int]$matches['count']
        } elseif ($line -match '^Failed\s*:\s*(?<count>\d+)$') {
            $snapshot.Failed = [int]$matches['count']
        } elseif ($line -match '^DryRun\s*:\s*(?<count>\d+)$') {
            $snapshot.DryRun = [int]$matches['count']
        }
    }

    return [pscustomobject]$snapshot
}

Export-ModuleMember -Function `
    Get-VideoArchivePresetDefinitions, `
    Save-VideoArchivePresetDefinitions, `
    Format-VideoArchiveQueueFlags, `
    New-VideoArchiveQueueItem, `
    ConvertTo-VideoArchiveCliArguments, `
    Get-VideoArchiveHistoryFiles, `
    Get-VideoArchiveFileTail, `
    Find-VideoArchiveLogPathFromLines, `
    Get-VideoArchiveProgressSnapshotFromLines
