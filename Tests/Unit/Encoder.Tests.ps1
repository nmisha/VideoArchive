Import-Module "$PSScriptRoot\..\..\Modules\Encoder.psm1" -Force

Describe 'Encoder' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveEncoder_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $nvencPath = Join-Path $tempRoot 'nvenc.cmd'
        $qsvPath = Join-Path $tempRoot 'qsv.cmd'
        $ffmpegPath = Join-Path $tempRoot 'ffmpeg.cmd'

        @'
@echo --no-i-adapt --no-b-adapt --device --weightp --aud --repeat-headers
'@ | Set-Content -LiteralPath $nvencPath -Encoding ascii

        @'
@echo --device --weightp --aud
'@ | Set-Content -LiteralPath $qsvPath -Encoding ascii

        @'
@echo ffmpeg help
'@ | Set-Content -LiteralPath $ffmpegPath -Encoding ascii

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
}
