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

function Get-OptionalDecisionProperty {
    param([psobject]$Object, [string]$Name, $DefaultValue)

    if ($null -eq $Object) { return $DefaultValue }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
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

        [string]$RequiredSidecarFile,

        [string]$SourcePath,

        [string]$PresetName,

        [string]$TargetCodec = 'HEVC',

        [switch]$Force,

        [switch]$NoSmartSkip,

        [ValidateSet('none', 'metadata', 'physical')]
        [string]$RotationMode = 'none',

        [ValidateSet(0, 90, 180, 270)]
        [int]$RotationDegrees = 0
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
        if (-not [string]::IsNullOrWhiteSpace($RequiredSidecarFile) -and -not (Test-Path -LiteralPath $RequiredSidecarFile -PathType Leaf)) {
            return [pscustomobject]@{
                Action = 'Encode'
                Reason = "Output exists but required metadata sidecar is missing: $RequiredSidecarFile"
                OutputGroup = $outputGroup
                SmartSkipApplied = $true
            }
        }

        return [pscustomobject]@{
            Action = 'Skip'
            Reason = "Output already exists: $OutputFile"
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        $SourcePath = [string](Get-OptionalDecisionProperty -Object $VideoInfo -Name 'Path' -DefaultValue '')
    }
    $sourceExtension = [System.IO.Path]::GetExtension($SourcePath).ToLowerInvariant()
    $legacyExtensions = @(
        Get-OptionalDecisionProperty -Object $SmartSkip -Name 'legacySourceExtensions' -DefaultValue @('.mts', '.m2ts', '.avi', '.wmv', '.webm')
    )
    $isLegacySource = -not [string]::IsNullOrWhiteSpace($sourceExtension) -and $legacyExtensions -contains $sourceExtension
    if ($isLegacySource) {
        return [pscustomobject]@{
            Action = 'Encode'
            Reason = "Legacy source container $sourceExtension requires archive transcode"
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
            ProtectOutputFromSavingsDiscard = $true
        }
    }

    if ($RotationMode -ne 'none' -and $RotationDegrees -ne 0) {
        return [pscustomobject]@{
            Action = 'Encode'
            Reason = if ($RotationMode -eq 'metadata') { "Metadata rotation by $RotationDegrees degrees" } else { "Physical rotation by $RotationDegrees degrees" }
            OutputGroup = $outputGroup
            SmartSkipApplied = $false
            ProtectOutputFromSavingsDiscard = $true
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
        $encodeSmallModernFiles = [bool](Get-OptionalDecisionProperty -Object $SmartSkip -Name 'encodeSmallModernFiles' -DefaultValue $false)
        if ($encodeSmallModernFiles) {
            return [pscustomobject]@{
                Action = 'Encode'
                Reason = "Small modern source encoding enabled ($($VideoInfo.SourceSizeMb) MB below $($SmartSkip.skipSmallFilesMb) MB)"
                OutputGroup = $outputGroup
                SmartSkipApplied = $true
                ProtectOutputFromSavingsDiscard = $true
            }
        }

        return [pscustomobject]@{
            Action = 'Skip'
            Reason = "Source is smaller than $($SmartSkip.skipSmallFilesMb) MB"
            OutputGroup = $outputGroup
            SmartSkipApplied = $true
            ProtectOutputFromSavingsDiscard = $false
        }
    }

    if ($VideoInfo.Codec -eq 'HEVC' -and $null -ne $VideoInfo.BitrateMbps) {
        $threshold = Get-HevcThresholdMbps -VideoInfo $VideoInfo -SmartSkip $SmartSkip
        if ($VideoInfo.BitrateMbps -lt $threshold) {
            $isProtectedHdrType = $VideoInfo.IsHdr -and @('HDR Vivid', 'Dolby Vision', 'HDR10+') -contains [string]$VideoInfo.HdrType
            if ($isProtectedHdrType) {
                return [pscustomobject]@{
                    Action = 'Encode'
                    Reason = "$($VideoInfo.HdrType) low-bitrate HDR is not skipped by Smart Skip"
                    OutputGroup = $outputGroup
                    SmartSkipApplied = $true
                }
            }

            $isArchivalHdr = $VideoInfo.IsHdr -and ([string]$PresetName -eq 'Archive')
            if ($isArchivalHdr -and -not @('HLG', 'HDR10') -contains [string]$VideoInfo.HdrType) {
                return [pscustomobject]@{
                    Action = 'Encode'
                    Reason = "Archive preset keeps HDR type $($VideoInfo.HdrType) for validation and metadata review"
                    OutputGroup = $outputGroup
                    SmartSkipApplied = $true
                }
            }

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
        Reason = "Codec $($VideoInfo.Codec) requires $($TargetCodec.ToUpperInvariant()) archive copy"
        OutputGroup = $outputGroup
        SmartSkipApplied = $true
    }
}

Export-ModuleMember -Function Get-EncodeDecision
