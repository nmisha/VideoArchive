Import-Module "$PSScriptRoot\..\..\Modules\DecisionEngine.psm1" -Force

Describe 'DecisionEngine' {
    It 'forces a requested physical rotation through Smart Skip' {
        $videoInfo = [pscustomobject]@{ IsHdr = $false; Codec = 'HEVC'; BitrateMbps = 1; Width = 1920; Height = 1080; SourceSizeMb = 1 }
        $smartSkip = [pscustomobject]@{ enabled = $true; skipIfOutputExists = $false; skipAv1 = $true; skipSmallFilesMb = 50; encodeSmallModernFiles = $false; legacySourceExtensions = @('.mts'); skipHevcBelowMbps1080p = 8; skipHevcBelowMbps4k = 15; skipHevcBelowMbps8k = 30 }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -SourcePath 'D:\in.mp4' -OutputFile 'D:\out.mp4' -SmartSkip $smartSkip -RotationMode physical -RotationDegrees 90

        $decision.Action | Should Be 'Encode'
        $decision.ProtectOutputFromSavingsDiscard | Should Be $true
        $decision.Reason | Should Match 'Physical rotation'
    }

    It 'treats a physical 270-degree rotation as an explicit transformation' {
        $videoInfo = [pscustomobject]@{ IsHdr = $false; Codec = 'HEVC'; BitrateMbps = 1; Width = 1920; Height = 1080; SourceSizeMb = 1 }
        $smartSkip = [pscustomobject]@{ enabled = $true; skipIfOutputExists = $false; skipAv1 = $true; skipSmallFilesMb = 50; encodeSmallModernFiles = $false; legacySourceExtensions = @('.mts'); skipHevcBelowMbps1080p = 8; skipHevcBelowMbps4k = 15; skipHevcBelowMbps8k = 30 }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -SourcePath 'D:\in.mp4' -OutputFile 'D:\out.mp4' -SmartSkip $smartSkip -RotationMode physical -RotationDegrees 270

        $decision.Action | Should Be 'Encode'
        $decision.Reason | Should Match '270'
    }

    BeforeAll {
        $smartSkip = [pscustomobject]@{
            enabled = $true
            skipAv1 = $true
            skipSmallFilesMb = 50
            encodeSmallModernFiles = $false
            legacySourceExtensions = @('.mts', '.m2ts', '.avi', '.wmv', '.webm')
            skipHevcBelowMbps1080p = 10
            skipHevcBelowMbps4k = 35
            skipHevcBelowMbps8k = 80
            skipIfOutputExists = $false
            deleteOutputIfSavingsBelowPercent = 3
        }
    }

    It 'skips AV1 when skipAv1 is enabled' {
        $videoInfo = [pscustomobject]@{
            Codec = 'AV1'
            IsHdr = $false
            Width = 1920
            Height = 1080
            BitrateMbps = 20
            SourceSizeMb = 200
        }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile 'D:\Out\file.mkv' -SmartSkip $smartSkip

        $decision.Action | Should Be 'Skip'
        $decision.Reason | Should Match 'AV1'
        $decision.OutputGroup | Should Be 'SDR'
    }

    It 'skips low bitrate HEVC 4K files' {
        $videoInfo = [pscustomobject]@{
            Codec = 'HEVC'
            IsHdr = $true
            HdrType = 'HLG'
            Width = 3840
            Height = 2160
            BitrateMbps = 20
            SourceSizeMb = 500
        }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile 'D:\Out\file.mkv' -SmartSkip $smartSkip

        $decision.Action | Should Be 'Skip'
        $decision.Reason | Should Match '35'
        $decision.OutputGroup | Should Be 'HDR'
    }

    It 'does not skip low bitrate HEVC HDR Vivid files by default' {
        $videoInfo = [pscustomobject]@{
            Codec = 'HEVC'
            IsHdr = $true
            HdrType = 'HDR Vivid'
            Width = 3840
            Height = 2160
            BitrateMbps = 20
            SourceSizeMb = 500
        }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile 'D:\Out\file.mkv' -SmartSkip $smartSkip

        $decision.Action | Should Be 'Encode'
        $decision.Reason | Should Match 'HDR Vivid'
    }

    It 'encodes when Force is enabled' {
        $videoInfo = [pscustomobject]@{
            Codec = 'AV1'
            IsHdr = $false
            Width = 1920
            Height = 1080
            BitrateMbps = 5
            SourceSizeMb = 20
        }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile 'D:\Out\file.mkv' -SmartSkip $smartSkip -Force

        $decision.Action | Should Be 'Encode'
        $decision.Reason | Should Be 'Force enabled'
    }

    It 'always encodes a small legacy MTS source' {
        $videoInfo = [pscustomobject]@{
            Path = 'D:\Camera\20120101003906.MTS'; Codec = 'AVC'; IsHdr = $false
            Width = 1920; Height = 1080; BitrateMbps = 18; SourceSizeMb = 39.56
        }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -SourcePath $videoInfo.Path -OutputFile 'D:\Out\file.mp4' -SmartSkip $smartSkip

        $decision.Action | Should Be 'Encode'
        $decision.Reason | Should Match 'Legacy source container .mts'
        $decision.ProtectOutputFromSavingsDiscard | Should Be $true
    }

    It 'skips a small modern source by default' {
        $videoInfo = [pscustomobject]@{
            Path = 'D:\Camera\small.mp4'; Codec = 'AVC'; IsHdr = $false
            Width = 1920; Height = 1080; BitrateMbps = 8; SourceSizeMb = 20
        }

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile 'D:\Out\file.mp4' -SmartSkip $smartSkip

        $decision.Action | Should Be 'Skip'
        $decision.Reason | Should Match 'smaller than 50 MB'
    }

    It 'encodes a small modern source when enabled' {
        $videoInfo = [pscustomobject]@{
            Path = 'D:\Camera\small.mp4'; Codec = 'AVC'; IsHdr = $false
            Width = 1920; Height = 1080; BitrateMbps = 8; SourceSizeMb = 20
        }
        $policy = $smartSkip.PSObject.Copy()
        $policy.encodeSmallModernFiles = $true

        $decision = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile 'D:\Out\file.mp4' -SmartSkip $policy

        $decision.Action | Should Be 'Encode'
        $decision.Reason | Should Match 'Small modern source encoding enabled'
        $decision.ProtectOutputFromSavingsDiscard | Should Be $true
    }

    It 're-encodes an existing MKV when its required sidecar is missing' {
        $outputFile = Join-Path $env:TEMP ('existing_' + [guid]::NewGuid().ToString('N') + '.mkv')
        try {
            Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8
            $videoInfo = [pscustomobject]@{
                Width = 1920; Height = 1080; Codec = 'AVC'; IsHdr = $false; HdrType = 'SDR'; BitrateMbps = 20; SourceSizeMb = 100
            }
            $smartSkip = [pscustomobject]@{
                enabled = $true; skipIfOutputExists = $true; skipAv1 = $false; skipSmallFilesMb = 0
                skipHevcBelowMbps8k = 60; skipHevcBelowMbps4k = 30; skipHevcBelowMbps1080p = 10
            }
            $sidecarPath = [System.IO.Path]::ChangeExtension($outputFile, '.metadata.json')

            $result = Get-EncodeDecision -VideoInfo $videoInfo -OutputFile $outputFile -RequiredSidecarFile $sidecarPath -SmartSkip $smartSkip

            $result.Action | Should Be 'Encode'
            $result.Reason | Should Match 'sidecar is missing'
        } finally {
            Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue
        }
    }
}
