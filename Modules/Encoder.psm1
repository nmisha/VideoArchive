Set-StrictMode -Version Latest

$script:EncoderOptionCache = @{}

function ConvertFrom-RigayaProgressLine {
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

function ConvertTo-NullableDoubleValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match(($Value -replace ',', '.'), '\d+(?:\.\d+)?')
    if (-not $match.Success) {
        return $null
    }

    return [double]::Parse($match.Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertFrom-FfmpegProgressLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,

        [Parameter(Mandatory)]
        [TimeSpan]$Elapsed,

        [Nullable[double]]$DurationSeconds
    )

    if ($Line -notmatch 'time=(?<time>\d+:\d+:\d+(?:\.\d+)?)') {
        return $null
    }

    try {
        $processed = [TimeSpan]::Parse($matches['time'], [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }

    $fps = $null
    $fpsText = $null
    if ($Line -match 'fps=\s*(?<fps>\d+(?:\.\d+)?)') {
        $fps = ConvertTo-NullableDoubleValue -Value $matches['fps']
        $fpsText = $matches['fps']
    }

    $percent = $null
    $percentText = $null
    $remainText = $null
    if ($null -ne $DurationSeconds -and $DurationSeconds -gt 0) {
        $percent = [math]::Min(100, [math]::Round(($processed.TotalSeconds / $DurationSeconds) * 100, 1))
        $percentText = ('{0:N1}%' -f $percent)
        if ($processed.TotalSeconds -gt 0 -and $processed.TotalSeconds -lt $DurationSeconds) {
            $remainingSeconds = ($DurationSeconds - $processed.TotalSeconds) * ($Elapsed.TotalSeconds / $processed.TotalSeconds)
            if ($remainingSeconds -gt 0) {
                $remainText = [TimeSpan]::FromSeconds($remainingSeconds).ToString('hh\:mm\:ss')
            }
        }
    }

    [pscustomobject]@{
        Percent = $percent
        PercentText = $percentText
        CurrentFrame = $null
        TotalFrames = $null
        FrameText = $null
        Fps = $fps
        FpsText = $fpsText
        RemainText = $remainText
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

function Test-EncoderOptionSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutablePath,

        [Parameter(Mandatory)]
        [string]$OptionName
    )

    if (-not $script:EncoderOptionCache.ContainsKey($ExecutablePath)) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $helpText = & $ExecutablePath --help 2>&1 | ForEach-Object { $_.ToString() } | Out-String
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        $script:EncoderOptionCache[$ExecutablePath] = if ([string]::IsNullOrWhiteSpace($helpText)) { '' } else { $helpText }
    }

    return $script:EncoderOptionCache[$ExecutablePath] -match "(?m)(^|\s)$([regex]::Escape($OptionName))(\s|,|$)"
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
                $_.Name -notlike '*_stdout_*' -and
                $_.Name -notlike '*_stderr_*'
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

function Get-AvailableEncoderBackends {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Tools
    )

    $backends = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$Tools.NvEnc) -and (Test-Path -LiteralPath $Tools.NvEnc -PathType Leaf)) { $backends += 'nvenc' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Tools.QsvEnc) -and (Test-Path -LiteralPath $Tools.QsvEnc -PathType Leaf)) { $backends += 'qsv' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Tools.AmfEnc) -and (Test-Path -LiteralPath $Tools.AmfEnc -PathType Leaf)) { $backends += 'amf' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Tools.Ffmpeg) -and (Test-Path -LiteralPath $Tools.Ffmpeg -PathType Leaf)) { $backends += 'software' }
    return @($backends)
}

function Test-BackendSupportsCodec {
    param(
        [Parameter(Mandatory)]
        [string]$Backend,

        [Parameter(Mandatory)]
        [string]$Codec
    )

    switch ($Backend) {
        'nvenc' { return @('hevc', 'av1') -contains $Codec }
        'qsv' { return @('hevc', 'av1') -contains $Codec }
        'amf' { return @('hevc') -contains $Codec }
        'software' { return @('hevc') -contains $Codec }
        default { return $false }
    }
}

function Resolve-OutputCodec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$VideoInfo,

        [Parameter(Mandatory)]
        [psobject]$EncoderConfig,

        [string]$RequestedCodec
    )

    $codec = if ([string]::IsNullOrWhiteSpace($RequestedCodec)) { [string]$EncoderConfig.defaultCodec } else { $RequestedCodec.ToLowerInvariant() }
    if ($codec -eq 'av1' -and $VideoInfo.IsHdr -and -not [bool]$EncoderConfig.allowHdrAv1) {
        return 'hevc'
    }

    return $codec
}

function Resolve-EncoderBackend {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Tools,

        [Parameter(Mandatory)]
        [psobject]$EncoderConfig,

        [Parameter(Mandatory)]
        [string]$Codec,

        [string]$RequestedBackend
    )

    $available = Get-AvailableEncoderBackends -Tools $Tools
    if ($available.Count -eq 0) {
        throw 'No available encoder backend was found.'
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedBackend) -and $RequestedBackend -ne 'auto') {
        if (-not ($available -contains $RequestedBackend)) {
            throw "Requested encoder backend '$RequestedBackend' is not available."
        }
        if (-not (Test-BackendSupportsCodec -Backend $RequestedBackend -Codec $Codec)) {
            throw "Encoder backend '$RequestedBackend' does not support codec '$Codec'."
        }
        return $RequestedBackend
    }

    $preferred = @([string[]]$EncoderConfig.autoBackendOrder)
    foreach ($backend in $preferred) {
        if (($available -contains $backend) -and (Test-BackendSupportsCodec -Backend $backend -Codec $Codec)) {
            return $backend
        }
    }

    foreach ($backend in $available) {
        if (Test-BackendSupportsCodec -Backend $backend -Codec $Codec) {
            return $backend
        }
    }

    throw "No available encoder backend supports codec '$Codec'."
}

function Get-RigayaExecutablePath {
    param(
        [Parameter(Mandatory)]
        [string]$Backend,

        [Parameter(Mandatory)]
        [psobject]$Tools
    )

    switch ($Backend) {
        'nvenc' { return $Tools.NvEnc }
        'qsv' { return $Tools.QsvEnc }
        'amf' { return $Tools.AmfEnc }
        default { throw "Backend '$Backend' is not a Rigaya backend." }
    }
}

function Get-X265PresetName {
    param([string]$NvPreset)

    switch ($NvPreset) {
        'p7' { return 'slower' }
        'p6' { return 'slow' }
        'p5' { return 'slow' }
        'p4' { return 'medium' }
        default { return 'medium' }
    }
}

function ConvertTo-FfmpegColorPrimaries {
    param([string]$Primaries)

    if ([string]::IsNullOrWhiteSpace($Primaries)) {
        return $null
    }

    if ($Primaries -match '2020') { return 'bt2020' }
    if ($Primaries -match '709') { return 'bt709' }
    return $null
}

function ConvertTo-FfmpegColorTransfer {
    param([string]$Transfer)

    if ([string]::IsNullOrWhiteSpace($Transfer)) {
        return $null
    }

    if ($Transfer -match 'HLG|ARIB') { return 'arib-std-b67' }
    if ($Transfer -match '2084|PQ') { return 'smpte2084' }
    if ($Transfer -match '709') { return 'bt709' }
    return $null
}

function ConvertTo-FfmpegColorMatrix {
    param([string]$Matrix)

    if ([string]::IsNullOrWhiteSpace($Matrix)) {
        return $null
    }

    if ($Matrix -match '2020') { return 'bt2020nc' }
    if ($Matrix -match '709') { return 'bt709' }
    return $null
}

function New-RigayaEncodeJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Backend,

        [Parameter(Mandatory)]
        [string]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [Parameter(Mandatory)]
        [psobject]$VideoInfo,

        [Parameter(Mandatory)]
        [psobject]$Tools,

        [Parameter(Mandatory)]
        [psobject]$Preset,

        [Parameter(Mandatory)]
        [psobject]$EncoderConfig,

        [Parameter(Mandatory)]
        [string]$Codec
    )

    $qvbr = if ($VideoInfo.IsHdr) { [string]$Preset.qvbrHdr } else { [string]$Preset.qvbrSdr }
    $executablePath = Get-RigayaExecutablePath -Backend $Backend -Tools $Tools
    $args = @(
        '--avsw'
        '-i', $InputFile
        '-o', $OutputFile
        '--codec', $Codec
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

    if ([string]$Preset.multipass -ne 'none' -and $Codec -eq 'hevc') {
        $args += @('--multipass', [string]$Preset.multipass)
    }

    if ([bool]$Preset.spatialAQ) { $args += '--aq' }
    if ([bool]$Preset.temporalAQ) { $args += '--aq-temporal' }
    if (-not [bool]$Preset.adaptiveI -and (Test-EncoderOptionSupported -ExecutablePath $executablePath -OptionName '--no-i-adapt')) { $args += '--no-i-adapt' }
    if (-not [bool]$Preset.adaptiveB -and (Test-EncoderOptionSupported -ExecutablePath $executablePath -OptionName '--no-b-adapt')) { $args += '--no-b-adapt' }
    if ([bool]$Preset.strictGop) { $args += '--strict-gop' }
    if ((Test-EncoderOptionSupported -ExecutablePath $executablePath -OptionName '--device')) {
        $args += @('--device', [string]$EncoderConfig.preferredGpu)
    }

    if ($VideoInfo.IsHdr) {
        if ($Codec -eq 'hevc') {
            $args += @('--profile', 'main10')
        }
        $args += @(
            '--output-depth', '10'
            '--transfer', 'auto'
            '--colorprim', 'auto'
            '--colormatrix', 'auto'
        )
    } else {
        if ($Codec -eq 'hevc') {
            $args += @('--profile', 'main')
        }
        $args += @('--output-depth', '8')
    }

    foreach ($optionalSwitch in @('--weightp', '--aud', '--repeat-headers')) {
        if (Test-EncoderOptionSupported -ExecutablePath $executablePath -OptionName $optionalSwitch) {
            $args += $optionalSwitch
        }
    }

    [pscustomobject]@{
        InputFile = $InputFile
        OutputFile = $OutputFile
        ExecutablePath = $executablePath
        Arguments = $args
        IsHdr = $VideoInfo.IsHdr
        PresetName = [string]$Preset.description
        Backend = $Backend
        Codec = $Codec
        TelemetryFormat = 'rigaya'
        EncoderLabel = [System.IO.Path]::GetFileName($executablePath)
        SourceDurationSeconds = $VideoInfo.DurationSeconds
    }
}

function New-SoftwareEncodeJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputFile,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [Parameter(Mandatory)]
        [psobject]$VideoInfo,

        [Parameter(Mandatory)]
        [psobject]$Tools,

        [Parameter(Mandatory)]
        [psobject]$Preset
    )

    $crf = if ($VideoInfo.IsHdr) { [string]$Preset.qvbrHdr } else { [string]$Preset.qvbrSdr }
    $x265Preset = Get-X265PresetName -NvPreset ([string]$Preset.nvPreset)
    $args = @(
        '-hide_banner'
        '-y'
        '-i', $InputFile
        '-map', '0'
        '-map_metadata', '0'
        '-map_chapters', '0'
        '-c:v', 'libx265'
        '-preset', $x265Preset
        '-pix_fmt', $(if ($VideoInfo.IsHdr) { 'yuv420p10le' } else { 'yuv420p' })
        '-c:a', 'copy'
        '-c:s', 'copy'
    )

    $x265Params = @("crf=$crf", 'repeat-headers=1')
    if ($VideoInfo.IsHdr) {
        $x265Params += 'hdr10-opt=1'
    }
    $args += @('-x265-params', ($x265Params -join ':'))

    $colorPrimaries = ConvertTo-FfmpegColorPrimaries -Primaries $VideoInfo.Primaries
    $colorTransfer = ConvertTo-FfmpegColorTransfer -Transfer $VideoInfo.Transfer
    $colorMatrix = ConvertTo-FfmpegColorMatrix -Matrix $VideoInfo.Matrix
    if (-not [string]::IsNullOrWhiteSpace($colorPrimaries)) { $args += @('-color_primaries', $colorPrimaries) }
    if (-not [string]::IsNullOrWhiteSpace($colorTransfer)) { $args += @('-color_trc', $colorTransfer) }
    if (-not [string]::IsNullOrWhiteSpace($colorMatrix)) { $args += @('-colorspace', $colorMatrix) }

    $args += $OutputFile

    [pscustomobject]@{
        InputFile = $InputFile
        OutputFile = $OutputFile
        ExecutablePath = $Tools.Ffmpeg
        Arguments = $args
        IsHdr = $VideoInfo.IsHdr
        PresetName = [string]$Preset.description
        Backend = 'software'
        Codec = 'hevc'
        TelemetryFormat = 'ffmpeg'
        EncoderLabel = [System.IO.Path]::GetFileName($Tools.Ffmpeg)
        SourceDurationSeconds = $VideoInfo.DurationSeconds
    }
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
        [psobject]$Tools,

        [Parameter(Mandatory)]
        [psobject]$Preset,

        [Parameter(Mandatory)]
        [psobject]$EncoderConfig,

        [string]$RequestedBackend,

        [string]$RequestedCodec
    )

    $codec = Resolve-OutputCodec -VideoInfo $VideoInfo -EncoderConfig $EncoderConfig -RequestedCodec $RequestedCodec
    $backend = Resolve-EncoderBackend -Tools $Tools -EncoderConfig $EncoderConfig -Codec $codec -RequestedBackend $RequestedBackend

    switch ($backend) {
        'nvenc' { return New-RigayaEncodeJob -Backend $backend -InputFile $InputFile -OutputFile $OutputFile -VideoInfo $VideoInfo -Tools $Tools -Preset $Preset -EncoderConfig $EncoderConfig -Codec $codec }
        'qsv' { return New-RigayaEncodeJob -Backend $backend -InputFile $InputFile -OutputFile $OutputFile -VideoInfo $VideoInfo -Tools $Tools -Preset $Preset -EncoderConfig $EncoderConfig -Codec $codec }
        'amf' { return New-RigayaEncodeJob -Backend $backend -InputFile $InputFile -OutputFile $OutputFile -VideoInfo $VideoInfo -Tools $Tools -Preset $Preset -EncoderConfig $EncoderConfig -Codec $codec }
        'software' { return New-SoftwareEncodeJob -InputFile $InputFile -OutputFile $OutputFile -VideoInfo $VideoInfo -Tools $Tools -Preset $Preset }
        default { throw "Unsupported encoder backend '$backend'." }
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
            Backend = $Job.Backend
            Codec = $Job.Codec
        }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $arguments = @($Job.Arguments)
    $logBuilder = New-Object System.Text.StringBuilder
    $stdoutPath = Join-Path -Path $outputDirectory -ChildPath ('encoder_stdout_{0}.log' -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path -Path $outputDirectory -ChildPath ('encoder_stderr_{0}.log' -f [guid]::NewGuid().ToString('N'))
    $stdoutIndex = 0
    $stderrIndex = 0
    $process = $null

    try {
        $process = Start-Process -FilePath $Job.ExecutablePath `
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
                        $telemetry = switch ($Job.TelemetryFormat) {
                            'ffmpeg' { ConvertFrom-FfmpegProgressLine -Line $line -Elapsed $stopwatch.Elapsed -DurationSeconds $Job.SourceDurationSeconds }
                            default { ConvertFrom-RigayaProgressLine -Line $line -Elapsed $stopwatch.Elapsed }
                        }
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

        throw ("{0} finished with exit code {1} but output file was not found. Expected='{2}'. Directory='{3}'. Files=[{4}]. Log: {5}" -f $Job.EncoderLabel, $exitCode, $Job.OutputFile, $outputDirectory, $directoryListing, $logBuilder.ToString().Trim())
    }

    [pscustomobject]@{
        Success = (($exitCode -eq 0) -and (-not $hasLogError))
        ExitCode = $exitCode
        OutputFile = $actualOutputFile
        Duration = $stopwatch.Elapsed
        CommandLine = @($Job.Arguments) -join ' '
        Log = $logBuilder.ToString().Trim()
        Backend = $Job.Backend
        Codec = $Job.Codec
    }
}

Export-ModuleMember -Function Get-ArchiveOutputExtension, New-EncodeJob, ConvertFrom-RigayaProgressLine, ConvertFrom-FfmpegProgressLine, Get-AvailableEncoderBackends, Resolve-OutputCodec, Resolve-EncoderBackend, Invoke-EncodeJob
