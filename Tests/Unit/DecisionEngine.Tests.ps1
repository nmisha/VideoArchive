Import-Module "$PSScriptRoot\..\..\Modules\DecisionEngine.psm1" -Force

Describe 'DecisionEngine' {
    BeforeAll {
        $smartSkip = [pscustomobject]@{
            enabled = $true
            skipAv1 = $true
            skipSmallFilesMb = 50
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
}
