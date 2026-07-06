Set-StrictMode -Version Latest

function Get-HevcThresholdMbps {
    param(
        [Parameter(Mandatory)]
        [psobject]$VideoInfo,

        [Parameter(Mandatory)]
        [psobject]$SmartSkip
    )

    $maxDimension = [math]::Max([int]$VideoInfo.Width, [int]$VideoInfo.Height)
    if ($maxDimension -ge 7680) {
        return [double]$SmartSkip.skipHevcBelowMbps8k
    }

    if ($maxDimension -ge 2160) {
        return [double]$SmartSkip.skipHevcBelowMbps4k
    }

    return [double]$SmartSkip.skipHevcBelowMbps1080p
}

function Get-EncodeDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$VideoInfo,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [Parameter(Mandatory)]
        [psobject]$SmartSkip,

        [switch]$Force,

        [switch]$NoSmartSkip
    )

    $outputGroup = if ($VideoInfo.IsHdr) { 'HDR' } else { 'SDR' }

    if ($Force) {
        return [pscustomobject]@{
            Action = 'Encode'
            Reason = 'Force enabled'
            OutputGroup = $outputGroup
            SmartSkipApplied = $false
        }
    }

    if ($NoSmartSkip -or -not [bool]$SmartSkip.enabled) {
        return [pscustomobject]@{
            Action = 'Encode'
            Reason = 'Smart Skip disabled'
            OutputGroup = $outputGroup
            SmartSkipApplied = $false
        }
    }

    if ([bool]$SmartSkip.skipIfOutputExists -and (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        return [pscustomobject]@{
            Action = 'Skip'
            Reason = "Output already exists: $OutputFile"
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
        }
    }

    if ([bool]$SmartSkip.skipAv1 -and $VideoInfo.Codec -eq 'AV1') {
        return [pscustomobject]@{
            Action = 'Skip'
            Reason = 'AV1 source skipped by Smart Skip'
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
        }
    }

    if ($null -ne $VideoInfo.SourceSizeMb -and $VideoInfo.SourceSizeMb -lt [double]$SmartSkip.skipSmallFilesMb) {
        return [pscustomobject]@{
            Action = 'Skip'
            Reason = "Source is smaller than $($SmartSkip.skipSmallFilesMb) MB"
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
        }
    }

    if ($VideoInfo.Codec -eq 'HEVC' -and $null -ne $VideoInfo.BitrateMbps) {
        $threshold = Get-HevcThresholdMbps -VideoInfo $VideoInfo -SmartSkip $SmartSkip
        if ($VideoInfo.BitrateMbps -lt $threshold) {
            return [pscustomobject]@{
                Action = 'Skip'
                Reason = "HEVC bitrate $($VideoInfo.BitrateMbps) Mbps is below $threshold Mbps threshold"
                OutputGroup = $outputGroup
                SmartSkipApplied = $true
            }
        }

        return [pscustomobject]@{
            Action = 'Encode'
            Reason = "HEVC bitrate $($VideoInfo.BitrateMbps) Mbps is above $threshold Mbps threshold"
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
        }
    }

    return [pscustomobject]@{
        Action = 'Encode'
        Reason = "Codec $($VideoInfo.Codec) requires HEVC archive copy"
        OutputGroup = $outputGroup
        SmartSkipApplied = $true
    }
}

Export-ModuleMember -Function Get-EncodeDecision
