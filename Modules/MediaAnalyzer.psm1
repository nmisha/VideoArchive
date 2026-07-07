Set-StrictMode -Version Latest

function Get-TrackValue {
    param(
        [psobject]$Track,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    if ($null -eq $Track) {
        return $null
    }

    foreach ($name in $Names) {
        $property = $Track.PSObject.Properties[$name]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }

    return $null
}

function ConvertTo-NormalizedCodec {
    param([string]$Codec)

    if ([string]::IsNullOrWhiteSpace($Codec)) {
        return $null
    }

    switch -Regex ($Codec.Trim()) {
        '^(HEVC|H\.265|V_MPEGH/ISO/HEVC)$' { return 'HEVC' }
        '^(AVC|H\.264|V_MPEG4/ISO/AVC)$' { return 'AVC' }
        '^AV1$' { return 'AV1' }
        '^VP9$' { return 'VP9' }
        default { return $Codec.Trim().ToUpperInvariant() }
    }
}

function ConvertTo-NormalizedAudioCodec {
    param([string]$Codec)

    if ([string]::IsNullOrWhiteSpace($Codec)) {
        return $null
    }

    switch -Regex ($Codec.Trim()) {
        '^(AAC|A_AAC.*|MPEG-4 AAC)$' { return 'AAC' }
        '^(AC-3|AC3|A_AC3)$' { return 'AC-3' }
        '^(E-AC-3|EAC3|EC-3|A_EAC3)$' { return 'E-AC-3' }
        '^(PCM|LPCM)$' { return 'PCM' }
        '^OPUS$' { return 'OPUS' }
        '^VORBIS$' { return 'VORBIS' }
        default { return $Codec.Trim().ToUpperInvariant() }
    }
}

function ConvertTo-NullableInt {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $match = [regex]::Match($Value, '\d+')
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Value
}

function ConvertTo-NullableDouble {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $normalized = ($Value -replace ',', '.')
    $match = [regex]::Match($normalized, '\d+(?:\.\d+)?')
    if (-not $match.Success) {
        return $null
    }

    return [double]::Parse($match.Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-BitrateMbps {
    param([string]$Value)

    $bitrate = ConvertTo-NullableDouble -Value $Value
    if ($null -eq $bitrate) {
        return $null
    }

    if ($bitrate -gt 10000) {
        return [math]::Round($bitrate / 1000000, 2)
    }

    return [math]::Round($bitrate, 2)
}

function Get-HdrClassification {
    param(
        [string]$Transfer,
        [string]$Primaries,
        [string]$HdrFormat,
        [int]$BitDepth
    )

    $transferText = [string]::Join(' ', @($Transfer, $HdrFormat))
    $primariesText = [string]$Primaries

    $isDolbyVision = $transferText -match 'Dolby\s*Vision'
    $isHdrVivid = $transferText -match 'HDR\s*Vivid|CUVA'
    $isHdr10Plus = $transferText -match 'HDR10\+'
    $isHlg = $transferText -match 'HLG|ARIB[\s\-]*STD[\s\-]*B67'
    $isPq = $transferText -match 'SMPTE[\s\-]*ST[\s\-]*2084|SMPTE[\s\-]*2084|PQ'
    $isHdr10 = ($transferText -match 'HDR10')
    $isUnknownHdr = (-not $isDolbyVision -and -not $isHdrVivid -and -not $isHdr10Plus -and -not $isHlg -and -not $isHdr10 -and -not $isPq -and $BitDepth -ge 10 -and $primariesText -match '2020')

    $isHdr = $isDolbyVision -or $isHdrVivid -or $isHdr10Plus -or $isHlg -or $isHdr10 -or $isPq -or $isUnknownHdr
    $hdrType = 'SDR'

    if ($isDolbyVision) {
        $hdrType = 'Dolby Vision'
    } elseif ($isHdrVivid) {
        $hdrType = 'HDR Vivid'
    } elseif ($isHdr10Plus) {
        $hdrType = 'HDR10+'
    } elseif ($isHlg) {
        $hdrType = 'HLG'
    } elseif ($isHdr10) {
        $hdrType = 'HDR10'
    } elseif ($isPq) {
        $hdrType = 'PQ'
    } elseif ($isUnknownHdr) {
        $hdrType = 'Unknown HDR'
    }

    [pscustomobject]@{
        IsHdr = $isHdr
        HdrType = $hdrType
    }
}

function ConvertFrom-MediaInfoJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MediaInfoJson,

        [string]$Path,

        [Nullable[long]]$SourceSizeBytes
    )

    $report = $MediaInfoJson | ConvertFrom-Json
    $tracks = @($report.media.track)
    $generalTrack = $tracks | Where-Object { $_.'@type' -eq 'General' } | Select-Object -First 1
    $videoTrack = $tracks | Where-Object { $_.'@type' -eq 'Video' } | Select-Object -First 1
    $audioTracks = @($tracks | Where-Object { $_.'@type' -eq 'Audio' })

    if ($null -eq $videoTrack) {
        throw "MediaInfo JSON does not contain a video track for '$Path'."
    }

    $codec = ConvertTo-NormalizedCodec (Get-TrackValue -Track $videoTrack -Names @('Format', 'CodecID', 'InternetMediaType'))
    $width = ConvertTo-NullableInt (Get-TrackValue -Track $videoTrack -Names @('Width'))
    $height = ConvertTo-NullableInt (Get-TrackValue -Track $videoTrack -Names @('Height'))
    $fps = ConvertTo-NullableDouble (Get-TrackValue -Track $videoTrack -Names @('FrameRate'))
    $bitDepth = ConvertTo-NullableInt (Get-TrackValue -Track $videoTrack -Names @('BitDepth'))
    $bitrateMbps = ConvertTo-BitrateMbps (Get-TrackValue -Track $videoTrack -Names @('BitRate', 'BitRate_Nominal'))
    $transfer = Get-TrackValue -Track $videoTrack -Names @('transfer_characteristics', 'Transfer_Characteristics', 'transfer_characteristics_Original')
    $primaries = Get-TrackValue -Track $videoTrack -Names @('colour_primaries', 'ColorPrimaries', 'colour_primaries_Source')
    $matrix = Get-TrackValue -Track $videoTrack -Names @('matrix_coefficients', 'Matrix_Coefficients', 'matrix_coefficients_Source')
    $rotation = ConvertTo-NullableDouble (Get-TrackValue -Track $videoTrack -Names @('Rotation'))
    $colorRange = Get-TrackValue -Track $videoTrack -Names @('colour_range', 'ColorRange', 'colour_range_Source')
    $dolbyVisionProfile = Get-TrackValue -Track $videoTrack -Names @('HDR_Format_Profile', 'HDR_Format_Profile_Compatibility')
    $audioInfo = @(
        foreach ($audioTrack in $audioTracks) {
            [pscustomobject]@{
                Codec = ConvertTo-NormalizedAudioCodec (Get-TrackValue -Track $audioTrack -Names @('Format', 'CodecID', 'InternetMediaType'))
                Channels = ConvertTo-NullableInt (Get-TrackValue -Track $audioTrack -Names @('Channel(s)', 'Channel_s_', 'Channels'))
                SamplingRate = ConvertTo-NullableInt (Get-TrackValue -Track $audioTrack -Names @('SamplingRate', 'SamplingRate_Original'))
            }
        }
    )

    $hdrParts = @(@(
        Get-TrackValue -Track $videoTrack -Names @('HDR_Format')
        Get-TrackValue -Track $videoTrack -Names @('HDR_Format_String')
        Get-TrackValue -Track $videoTrack -Names @('HDR_Format_Compatibility')
        Get-TrackValue -Track $videoTrack -Names @('HDR_Format_Commercial')
        Get-TrackValue -Track $videoTrack -Names @('HDR_Format_Settings')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hdrFormat = $null
    if ($hdrParts.Count -gt 0) {
        $hdrFormat = ($hdrParts | Select-Object -Unique) -join '; '
    }

    $hdr = Get-HdrClassification -Transfer $transfer -Primaries $primaries -HdrFormat $hdrFormat -BitDepth $bitDepth
    $durationSeconds = ConvertTo-NullableDouble (Get-TrackValue -Track $generalTrack -Names @('Duration'))
    if ($null -ne $durationSeconds -and $durationSeconds -gt 1000) {
        $durationSeconds = [math]::Round($durationSeconds / 1000, 3)
    }

    $result = [pscustomobject]@{
        Path = $Path
        Codec = $codec
        Width = $width
        Height = $height
        Fps = $fps
        BitDepth = $bitDepth
        BitrateMbps = $bitrateMbps
        Rotation = $rotation
        ColorRange = $colorRange
        Transfer = $transfer
        Primaries = $primaries
        Matrix = $matrix
        HDRFormat = $hdrFormat
        DolbyVisionProfile = $dolbyVisionProfile
        IsHdr = $hdr.IsHdr
        HdrType = $hdr.HdrType
        AudioTrackCount = $audioTracks.Count
        AudioTracks = $audioInfo
        AudioCodec = if ($audioInfo.Count -gt 0) { $audioInfo[0].Codec } else { $null }
        AudioChannels = if ($audioInfo.Count -gt 0) { $audioInfo[0].Channels } else { $null }
        AudioSamplingRate = if ($audioInfo.Count -gt 0) { $audioInfo[0].SamplingRate } else { $null }
        DurationSeconds = $durationSeconds
        SourceSizeBytes = $SourceSizeBytes
        SourceSizeMb = if ($null -ne $SourceSizeBytes) { [math]::Round($SourceSizeBytes / 1MB, 2) } else { $null }
    }

    return $result
}

function Get-VideoInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$MediaInfoPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Video file not found: $Path"
    }

    if (-not (Test-Path -LiteralPath $MediaInfoPath -PathType Leaf)) {
        throw "MediaInfo executable not found: $MediaInfoPath"
    }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $json = & $MediaInfoPath --Output=JSON --Full --Language=raw --BOM $Path 2>&1 | ForEach-Object { $_.ToString() } | Out-String
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "MediaInfo failed for '$Path': $json"
    }

    $file = Get-Item -LiteralPath $Path
    ConvertFrom-MediaInfoJson -MediaInfoJson $json -Path $file.FullName -SourceSizeBytes $file.Length
}

Export-ModuleMember -Function Get-VideoInfo, ConvertFrom-MediaInfoJson
