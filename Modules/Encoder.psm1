Set-StrictMode -Version Latest

$script:NvEncOptionCache = @{}

function ConvertFrom-NvEncProgressLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,

        [Parameter(Mandatory)]
        [TimeSpan]$Elapsed
    )

    $pattern = '^\[(?<percent>\d+(?:\.\d+)?)%\]\s+(?:(?<current>\d+)\/(?<total>\d+)|(?<currentOnly>\d+))\s+frames:\s+(?<fps>\d+(?:\.\d+)?)\s+fps,.*?remain\s+(?<remain>\d+:\d+:\d+)'
    $match = [regex]::Match($Line, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $currentFrame = if ($match.Groups['current'].Success) {
        [int]$match.Groups['current'].Value
    } else {
        [int]$match.Groups['currentOnly'].Value
    }

    $totalFrames = $null
    $frameText = '{0} frames' -f $currentFrame
    if ($match.Groups['total'].Success) {
        $totalFrames = [int]$match.Groups['total'].Value
        $frameText = '{0}/{1} frames' -f $currentFrame, $totalFrames
    }

    [pscustomobject]@{
        Percent = [double]$match.Groups['percent'].Value
        PercentText = ('{0}%' -f $match.Groups['percent'].Value)
        CurrentFrame = $currentFrame
        TotalFrames = $totalFrames
        FrameText = $frameText
        Fps = [double]$match.Groups['fps'].Value
        FpsText = $match.Groups['fps'].Value
        RemainText = $match.Groups['remain'].Value
        Elapsed = $Elapsed
        ElapsedText = $Elapsed.ToString('hh\:mm\:ss')
        RawLine = $Line
    }
}

function Read-AppendedLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [int]$StartIndex
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{
            Lines = @()
            NextIndex = $StartIndex
        }
    }

    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    if ($lines.Count -le $StartIndex) {
        return [pscustomobject]@{
            Lines = @()
            NextIndex = $lines.Count
        }
    }

    return [pscustomobject]@{
        Lines = @($lines[$StartIndex..($lines.Count - 1)])
        NextIndex = $lines.Count
    }
}

function Get-ArchiveOutputExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    switch ([System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant()) {
        '.mp4' { return '.mp4' }
        '.mov' { return '.mov' }
        '.m4v' { return '.m4v' }
        '.mkv' { return '.mkv' }
        default { return '.mkv' }
    }
}

function Test-NvEncOptionSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NvEncPath,

        [Parameter(Mandatory)]
        [string]$OptionName
    )

    if (-not $script:NvEncOptionCache.ContainsKey($NvEncPath)) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $helpText = & $NvEncPath --help 2>&1 | ForEach-Object { $_.ToString() } | Out-String
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $script:NvEncOptionCache[$NvEncPath] = if ([string]::IsNullOrWhiteSpace($helpText)) { '' } else { $helpText }
    }

    return $script:NvEncOptionCache[$NvEncPath] -match "(?m)(^|\s)$([regex]::Escape($OptionName))(\s|,|$)"
}

function Resolve-EncodeOutputFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExpectedOutputFile
    )

    if (Test-Path -LiteralPath $ExpectedOutputFile -PathType Leaf) {
        return $ExpectedOutputFile
    }

    $outputDirectory = Split-Path -Path $ExpectedOutputFile -Parent
    $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($ExpectedOutputFile)
    $expectedExtension = [System.IO.Path]::GetExtension($ExpectedOutputFile)

    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        return $null
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $outputDirectory -File -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -notlike 'nvenc_stdout_*' -and
                $_.Name -notlike 'nvenc_stderr_*'
            }
    )

    $exactBaseNameCandidates = @(
        $candidates | Where-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $expectedName
        }
    )

    if ($exactBaseNameCandidates.Count -eq 1) {
        return $exactBaseNameCandidates[0].FullName
    }

    $sameExtensionCandidates = @(
        $candidates | Where-Object { $_.Extension -ieq $expectedExtension }
    )

    if ($sameExtensionCandidates.Count -eq 1) {
        return $sameExtensionCandidates[0].FullName
    }

    return $null
}

function New-EncodeJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [Parameter(Mandatory)]
        [psobject]$VideoInfo,

        [Parameter(Mandatory)]
        [string]$NvEncPath,

        [Parameter(Mandatory)]
        [psobject]$Preset
    )

    $qvbr = if ($VideoInfo.IsHdr) {
        [string]$Preset.qvbrHdr
    } else {
        [string]$Preset.qvbrSdr
    }

    $args = @(
        '--avsw'
        '-i', $InputFile
        '-o', $OutputFile
        '--codec', 'hevc'
        '--preset', [string]$Preset.nvPreset
        '--qvbr', $qvbr
        '--lookahead', [string]$Preset.lookahead
        '--aq-strength', [string]$Preset.aqStrength
        '--bframes', [string]$Preset.bFrames
        '--ref', [string]$Preset.refFrames
        '--gop-len', 'auto'
        '--audio-copy'
        '--video-metadata', 'copy'
        '--chapter-copy'
        '--log-level', 'info'
        '--process-codepage', 'utf8'
    )

    if ([string]$Preset.multipass -ne 'none') {
        $args += @('--multipass', [string]$Preset.multipass)
    }

    if ([bool]$Preset.spatialAQ) {
        $args += '--aq'
    }

    if ([bool]$Preset.temporalAQ) {
        $args += '--aq-temporal'
    }

    if (-not [bool]$Preset.adaptiveI -and (Test-NvEncOptionSupported -NvEncPath $NvEncPath -OptionName '--no-i-adapt')) {
        $args += '--no-i-adapt'
    }

    if (-not [bool]$Preset.adaptiveB -and (Test-NvEncOptionSupported -NvEncPath $NvEncPath -OptionName '--no-b-adapt')) {
        $args += '--no-b-adapt'
    }

    if ([bool]$Preset.strictGop) {
        $args += '--strict-gop'
    }

    if ($VideoInfo.IsHdr) {
        $args += @(
            '--profile', 'main10'
            '--output-depth', '10'
            '--transfer', 'auto'
            '--colorprim', 'auto'
            '--colormatrix', 'auto'
        )
    } else {
        $args += @(
            '--profile', 'main'
            '--output-depth', '8'
        )
    }

    foreach ($optionalSwitch in @('--weightp', '--aud', '--repeat-headers')) {
        if (Test-NvEncOptionSupported -NvEncPath $NvEncPath -OptionName $optionalSwitch) {
            $args += $optionalSwitch
        }
    }

    [pscustomobject]@{
        InputFile = $InputFile
        OutputFile = $OutputFile
        NvEncPath = $NvEncPath
        Arguments = $args
        IsHdr = $VideoInfo.IsHdr
        PresetName = $Preset.PSObject.Properties['description'].Value
    }
}

function Invoke-EncodeJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Job,

        [switch]$DryRun,

        [scriptblock]$ProgressCallback
    )

    $outputDirectory = Split-Path -Path $Job.OutputFile -Parent
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    if ($DryRun) {
        return [pscustomobject]@{
            Success = $true
            ExitCode = 0
            OutputFile = $Job.OutputFile
            Duration = [TimeSpan]::Zero
            CommandLine = @($Job.Arguments) -join ' '
            Log = 'Dry run'
        }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $arguments = @($Job.Arguments)
    $logBuilder = New-Object System.Text.StringBuilder
    $outputDirectory = Split-Path -Path $Job.OutputFile -Parent
    $stdoutPath = Join-Path -Path $outputDirectory -ChildPath ('nvenc_stdout_{0}.log' -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path -Path $outputDirectory -ChildPath ('nvenc_stderr_{0}.log' -f [guid]::NewGuid().ToString('N'))
    $stdoutIndex = 0
    $stderrIndex = 0
    $process = $null

    try {
        $process = Start-Process -FilePath $Job.NvEncPath `
            -ArgumentList $arguments `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath `
            -NoNewWindow `
            -PassThru

        while (-not $process.HasExited) {
            $stdoutUpdate = Read-AppendedLines -Path $stdoutPath -StartIndex $stdoutIndex
            $stderrUpdate = Read-AppendedLines -Path $stderrPath -StartIndex $stderrIndex

            foreach ($streamUpdate in @($stdoutUpdate, $stderrUpdate)) {
                foreach ($line in $streamUpdate.Lines) {
                    if ([string]::IsNullOrWhiteSpace($line)) {
                        continue
                    }

                    [void]$logBuilder.AppendLine($line)
                    if ($null -ne $ProgressCallback) {
                        $telemetry = ConvertFrom-NvEncProgressLine -Line $line -Elapsed $stopwatch.Elapsed
                        if ($null -ne $telemetry) {
                            & $ProgressCallback $telemetry
                        }
                    }
                }
            }

            $stdoutIndex = $stdoutUpdate.NextIndex
            $stderrIndex = $stderrUpdate.NextIndex
            Start-Sleep -Milliseconds 500
        }

        $process.WaitForExit()
        $process.Refresh()

        $stdoutUpdate = Read-AppendedLines -Path $stdoutPath -StartIndex $stdoutIndex
        $stderrUpdate = Read-AppendedLines -Path $stderrPath -StartIndex $stderrIndex
        foreach ($streamUpdate in @($stdoutUpdate, $stderrUpdate)) {
            foreach ($line in $streamUpdate.Lines) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    [void]$logBuilder.AppendLine($line)
                }
            }
        }

        $exitCode = [int]$process.ExitCode
    } finally {
        $stopwatch.Stop()
        if ($null -ne $process) {
            $process.Dispose()
        }
        if (Test-Path -LiteralPath $stdoutPath) {
            Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    $hasLogError = $logBuilder.ToString() -match '(?m)^\s*Error:'
    $actualOutputFile = Resolve-EncodeOutputFile -ExpectedOutputFile $Job.OutputFile
    if ([string]::IsNullOrWhiteSpace($actualOutputFile)) {
        $directoryListing = if (Test-Path -LiteralPath $outputDirectory -PathType Container) {
            (Get-ChildItem -LiteralPath $outputDirectory -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', '
        } else {
            '<missing output directory>'
        }

        throw ("NVEncC finished with exit code {0} but output file was not found. Expected='{1}'. Directory='{2}'. Files=[{3}]. NVEncC log: {4}" -f $exitCode, $Job.OutputFile, $outputDirectory, $directoryListing, $logBuilder.ToString().Trim())
    }

    [pscustomobject]@{
        Success = (($exitCode -eq 0) -and (-not $hasLogError))
        ExitCode = $exitCode
        OutputFile = $actualOutputFile
        Duration = $stopwatch.Elapsed
        CommandLine = @($Job.Arguments) -join ' '
        Log = $logBuilder.ToString().Trim()
    }
}

Export-ModuleMember -Function Get-ArchiveOutputExtension, New-EncodeJob, ConvertFrom-NvEncProgressLine, Invoke-EncodeJob
