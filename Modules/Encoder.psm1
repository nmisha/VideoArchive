Set-StrictMode -Version Latest

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
        '--multipass', [string]$Preset.multipass
        '--aq'
        '--aq-strength', [string]$Preset.aqStrength
        '--audio-copy'
        '--video-metadata', 'copy'
        '--chapter-copy'
        '--log-level', 'info'
        '--process-codepage', 'utf8'
    )

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

        [switch]$DryRun
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
    $log = & $Job.NvEncPath @arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()

    [pscustomobject]@{
        Success = ($exitCode -eq 0)
        ExitCode = $exitCode
        OutputFile = $Job.OutputFile
        Duration = $stopwatch.Elapsed
        CommandLine = @($Job.Arguments) -join ' '
        Log = $log.Trim()
    }
}

Export-ModuleMember -Function Get-ArchiveOutputExtension, New-EncodeJob, Invoke-EncodeJob
