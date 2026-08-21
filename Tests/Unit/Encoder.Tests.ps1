Import-Module "$PSScriptRoot\..\..\Modules\Encoder.psm1" -Force

Describe 'Encoder' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveEncoder_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $nvencPath = Join-Path $tempRoot 'nvenc.cmd'
        $qsvPath = Join-Path $tempRoot 'qsv.cmd'
        $ffmpegPath = Join-Path $tempRoot 'ffmpeg.cmd'
        $argumentEchoPath = Join-Path $tempRoot 'argument-echo.cmd'

        @'
@echo --no-i-adapt --no-b-adapt --device --weightp --aud --repeat-headers
'@ | Set-Content -LiteralPath $nvencPath -Encoding ascii

        @'
@echo --device --weightp --aud
'@ | Set-Content -LiteralPath $qsvPath -Encoding ascii

        @'
@echo ffmpeg help
'@ | Set-Content -LiteralPath $ffmpegPath -Encoding ascii

        @'
@echo off
set "input="
set "output="
:loop
if "%~1"=="" goto done
if /i "%~1"=="-i" set "input=%~2"
if /i "%~1"=="-o" set "output=%~2"
shift
goto loop
:done
echo INPUT=%input%
type nul > "%output%"
exit /b 0
'@ | Set-Content -LiteralPath $argumentEchoPath -Encoding ascii

        $tools = [pscustomobject]@{
            NvEnc = $nvencPath
            QsvEnc = $qsvPath
            AmfEnc = $null
            Ffmpeg = $ffmpegPath
        }

        $encoderConfig = [pscustomobject]@{
            defaultBackend = 'auto'
            defaultCodec = 'hevc'
            allowHdrAv1 = $false
            autoBackendOrder = @('nvenc', 'qsv', 'amf', 'software')
            preferredGpu = 1
        }

        $preset = [pscustomobject]@{
            description = 'Test preset'
            qvbrHdr = 18
            qvbrSdr = 20
            nvPreset = 'p5'
            lookahead = 16
            multipass = '2pass-quarter'
            aqStrength = 8
            bFrames = 4
            refFrames = 4
            spatialAQ = $true
            temporalAQ = $true
            adaptiveI = $true
            adaptiveB = $true
            strictGop = $false
        }
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'falls back from requested HDR AV1 to HEVC when HDR AV1 is disabled' {
        $videoInfo = [pscustomobject]@{ IsHdr = $true }

        $codec = Resolve-OutputCodec -VideoInfo $videoInfo -EncoderConfig $encoderConfig -RequestedCodec 'av1'

        $codec | Should Be 'hevc'
    }

    It 'auto-selects NVENC for AV1 when available' {
        $backend = Resolve-EncoderBackend -Tools $tools -EncoderConfig $encoderConfig -Codec 'av1'

        $backend | Should Be 'nvenc'
    }

    It 'builds an NVENC AV1 job for SDR when requested' {
        $videoInfo = [pscustomobject]@{
            IsHdr = $false
            Primaries = 'BT.709'
            Transfer = 'BT.709'
            Matrix = 'BT.709'
            DurationSeconds = 120
        }

        $job = New-EncodeJob -InputFile 'D:\in.mp4' -OutputFile 'D:\out.mp4' -VideoInfo $videoInfo -Tools $tools -Preset $preset -EncoderConfig $encoderConfig -RequestedCodec 'av1'

        $job.Backend | Should Be 'nvenc'
        $job.Codec | Should Be 'av1'
        ($job.Arguments -join ' ') | Should Match '--codec av1'
        ($job.Arguments -join ' ') | Should Match '--device 1'
    }

    It 'uses software fallback when explicitly requested' {
        $videoInfo = [pscustomobject]@{
            IsHdr = $false
            Primaries = 'BT.709'
            Transfer = 'BT.709'
            Matrix = 'BT.709'
            DurationSeconds = 180
        }

        $job = New-EncodeJob -InputFile 'D:\in.mp4' -OutputFile 'D:\out.mp4' -VideoInfo $videoInfo -Tools $tools -Preset $preset -EncoderConfig $encoderConfig -RequestedBackend 'software'

        $job.Backend | Should Be 'software'
        $job.Codec | Should Be 'hevc'
        ($job.Arguments -join ' ') | Should Match 'libx265'
        ($job.Arguments -join ' ') | Should Match 'crf=20'
    }

    It 'quotes Windows command line paths containing spaces' {
        $encoderModule = Get-Module Encoder
        $commandLine = & $encoderModule {
            ConvertTo-WindowsCommandLine -Arguments @(
                '--avsw',
                '-i',
                'D:\Video archive\City day\00000.MTS',
                '-o',
                'D:\Video archive\Encoded files\00000.mkv'
            )
        }

        $commandLine | Should Be '--avsw -i "D:\Video archive\City day\00000.MTS" -o "D:\Video archive\Encoded files\00000.mkv"'
    }

    It 'passes paths containing spaces as single native process arguments' {
        $outputFile = Join-Path $tempRoot 'Encoded files\result.mkv'
        $inputFile = 'D:\Video archive\City day\00000.MTS'
        $job = [pscustomobject]@{
            InputFile = $inputFile
            OutputFile = $outputFile
            ExecutablePath = $argumentEchoPath
            Arguments = @('-i', $inputFile, '-o', $outputFile)
            Backend = 'test'
            Codec = 'hevc'
            TelemetryFormat = 'rigaya'
            EncoderLabel = 'argument-echo.cmd'
            SourceDurationSeconds = 1
        }

        $result = Invoke-EncodeJob -Job $job

        $result.Success | Should Be $true
        $result.Log | Should Be "INPUT=$inputFile"
        $result.OutputFile | Should Be $outputFile
    }
}
