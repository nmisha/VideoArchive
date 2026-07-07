Set-StrictMode -Version Latest

function Test-StringContainsNormalized {
    param(
        [string]$Actual,
        [string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Expected)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Actual)) {
        return $false
    }

    $normalizedActual = ($Actual -replace '\s+', '').ToLowerInvariant()
    $normalizedExpected = ($Expected -replace '\s+', '').ToLowerInvariant()
    return $normalizedActual.Contains($normalizedExpected)
}

function Test-StringEquivalentNormalized {
    param(
        [string]$Actual,
        [string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Actual) -and [string]::IsNullOrWhiteSpace($Expected)) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Actual) -or [string]::IsNullOrWhiteSpace($Expected)) {
        return $false
    }

    $normalizedActual = ($Actual -replace '\s+', '').ToLowerInvariant()
    $normalizedExpected = ($Expected -replace '\s+', '').ToLowerInvariant()
    return ($normalizedActual -eq $normalizedExpected) -or
        $normalizedActual.Contains($normalizedExpected) -or
        $normalizedExpected.Contains($normalizedActual)
}

function ConvertTo-TimezoneAdjustedDate {
    param(
        [Parameter(Mandatory)]
        [datetime]$DateTime,

        [string]$Offset = '+00:00'
    )

    if ([string]::IsNullOrWhiteSpace($Offset) -or $Offset -eq '+00:00') {
        return $DateTime
    }

    $match = [regex]::Match($Offset.Trim(), '^(?<sign>[+\-])(?<hours>\d{2}):(?<minutes>\d{2})$')
    if (-not $match.Success) {
        return $DateTime
    }

    $hours = [int]$match.Groups['hours'].Value
    $minutes = [int]$match.Groups['minutes'].Value
    $timeSpan = New-TimeSpan -Hours $hours -Minutes $minutes
    if ($match.Groups['sign'].Value -eq '-') {
        $timeSpan = -$timeSpan
    }

    return $DateTime.Add($timeSpan)
}

function Test-MetadataPreserved {
    [CmdletBinding()]
    param(
        [psobject]$SourceMetadata,

        [psobject]$OutputMetadata,

        [double]$GpsTolerance = 0.0001
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if ($null -eq $SourceMetadata -or $null -eq $OutputMetadata) {
        return @($errors)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$SourceMetadata.DateTaken)) {
        if (-not (Test-StringEquivalentNormalized -Actual $OutputMetadata.DateTaken -Expected $SourceMetadata.DateTaken)) {
            $errors.Add("DateTaken mismatch: '$($SourceMetadata.DateTaken)' -> '$($OutputMetadata.DateTaken)'")
        }
    }

    if ($SourceMetadata.HasGps) {
        if (-not $OutputMetadata.HasGps) {
            $errors.Add('GPS metadata missing in output')
        } else {
            $latitudeDelta = [math]::Abs(([double]$SourceMetadata.GpsLatitude) - ([double]$OutputMetadata.GpsLatitude))
            $longitudeDelta = [math]::Abs(([double]$SourceMetadata.GpsLongitude) - ([double]$OutputMetadata.GpsLongitude))
            if ($latitudeDelta -gt $GpsTolerance -or $longitudeDelta -gt $GpsTolerance) {
                $errors.Add("GPS mismatch: [$($SourceMetadata.GpsLatitude), $($SourceMetadata.GpsLongitude)] -> [$($OutputMetadata.GpsLatitude), $($OutputMetadata.GpsLongitude)]")
            }
        }
    }

    return @($errors)
}

function Test-CaptureDateValidation {
    [CmdletBinding()]
    param(
        [psobject]$CaptureDateResult,

        [psobject]$OutputMetadata,

        [bool]$StrictDateMode,

        [double]$ToleranceSeconds = 2
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]

    if ($null -eq $CaptureDateResult) {
        return [pscustomobject]@{
            Warnings = @($warnings)
            Errors = @($errors)
        }
    }

    if (-not $CaptureDateResult.Success) {
        foreach ($warning in @($CaptureDateResult.Warnings)) {
            $warnings.Add($warning)
        }

        if ($StrictDateMode) {
            $errors.Add('Capture date could not be determined in strict date mode.')
        }

        return [pscustomobject]@{
            Warnings = @($warnings)
            Errors = @($errors)
        }
    }

    if ($null -eq $OutputMetadata) {
        $errors.Add('Output metadata are not available for capture date validation.')
        return [pscustomobject]@{
            Warnings = @($warnings)
            Errors = @($errors)
        }
    }

    $candidateDates = @(
        $OutputMetadata.QuickTimeMediaCreateDate
        $OutputMetadata.QuickTimeCreateDate
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($candidateDates.Count -eq 0) {
        $errors.Add('Output capture date tags are missing.')
        return [pscustomobject]@{
            Warnings = @($warnings)
            Errors = @($errors)
        }
    }

    $expected = $CaptureDateResult.DateTime
    $matched = $false
    foreach ($candidateDate in $candidateDates) {
        try {
            $actual = [datetime]::Parse($candidateDate, [System.Globalization.CultureInfo]::InvariantCulture)
            if ([math]::Abs(($expected - $actual).TotalSeconds) -le $ToleranceSeconds) {
                $matched = $true
                break
            }
        } catch {
        }
    }

    if (-not $matched) {
        $errors.Add("Capture date mismatch: expected $($expected.ToString('yyyy-MM-ddTHH:mm:ss'))")
    }

    [pscustomobject]@{
        Warnings = @($warnings)
        Errors = @($errors)
    }
}

function Test-HdrCompatibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceInfo,

        [Parameter(Mandatory)]
        [psobject]$OutputInfo
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]

    if ($SourceInfo.IsHdr) {
        if (-not $OutputInfo.IsHdr) {
            $errors.Add('HDR source became SDR')
        } else {
            if ($OutputInfo.BitDepth -lt 10) {
                $errors.Add("HDR output bit depth must be at least 10-bit, got $($OutputInfo.BitDepth)")
            }

            if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Primaries) -and $SourceInfo.Primaries -match '2020') {
                if (-not (Test-StringEquivalentNormalized -Actual $OutputInfo.Primaries -Expected $SourceInfo.Primaries)) {
                    $errors.Add("Primaries mismatch: '$($SourceInfo.Primaries)' -> '$($OutputInfo.Primaries)'")
                }
            }

            if ([string]$SourceInfo.HdrType -eq 'HDR Vivid' -and [string]$OutputInfo.HdrType -eq 'HLG') {
                $warnings.Add('HDR Vivid metadata were not preserved; base HLG HDR preserved')
            } elseif (-not [string]::IsNullOrWhiteSpace($SourceInfo.Transfer)) {
                if (-not (Test-StringEquivalentNormalized -Actual $OutputInfo.Transfer -Expected $SourceInfo.Transfer)) {
                    $errors.Add("Transfer mismatch: '$($SourceInfo.Transfer)' -> '$($OutputInfo.Transfer)'")
                }
            }
        }
    } elseif ($OutputInfo.IsHdr) {
        $errors.Add("SDR source unexpectedly became HDR ($($OutputInfo.HdrType))")
    }

    return [pscustomobject]@{
        Warnings = @($warnings)
        Errors = @($errors)
    }
}

function Test-FileTimestampsPreserved {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [double]$CreationToleranceSeconds = 2,

        [double]$LastWriteToleranceSeconds = 2,

        [double]$LastAccessToleranceSeconds = 2,

        [Nullable[datetime]]$ExpectedCreationTime,

        [Nullable[datetime]]$ExpectedLastWriteTime,

        [Nullable[datetime]]$ExpectedLastAccessTime
    )

    $source = Get-Item -LiteralPath $SourceFile
    $output = Get-Item -LiteralPath $OutputFile
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    $expectedCreationTime = if ($null -ne $ExpectedCreationTime) { $ExpectedCreationTime } else { $source.CreationTime }
    $expectedLastWriteTime = if ($null -ne $ExpectedLastWriteTime) { $ExpectedLastWriteTime } else { $source.LastWriteTime }
    $expectedLastAccessTime = if ($null -ne $ExpectedLastAccessTime) { $ExpectedLastAccessTime } else { $source.LastAccessTime }

    $creationDelta = [math]::Abs(($expectedCreationTime - $output.CreationTime).TotalSeconds)
    if ($creationDelta -gt $CreationToleranceSeconds) {
        $errors.Add("CreationTime mismatch: $($expectedCreationTime) -> $($output.CreationTime) (delta ${creationDelta}s)")
    }

    $lastWriteDelta = [math]::Abs(($expectedLastWriteTime - $output.LastWriteTime).TotalSeconds)
    if ($lastWriteDelta -gt $LastWriteToleranceSeconds) {
        $errors.Add("LastWriteTime mismatch: $($expectedLastWriteTime) -> $($output.LastWriteTime) (delta ${lastWriteDelta}s)")
    }

    $lastAccessDelta = [math]::Abs(($expectedLastAccessTime - $output.LastAccessTime).TotalSeconds)
    if ($lastAccessDelta -gt $LastAccessToleranceSeconds) {
        $warnings.Add("LastAccessTime mismatch: $($expectedLastAccessTime) -> $($output.LastAccessTime) (delta ${lastAccessDelta}s)")
    }

    return [pscustomobject]@{
        Errors = @($errors)
        Warnings = @($warnings)
    }
}

function Test-EncodedVideo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [psobject]$SourceInfo,

        [Parameter(Mandatory)]
        [psobject]$OutputInfo,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [switch]$ValidateTimestamps,

        [double]$FpsTolerance = 0.2,

        [double]$RotationTolerance = 0.1,

        [psobject]$SourceMetadata,

        [psobject]$OutputMetadata,

        [psobject]$CaptureDateResult,

        [bool]$StrictDateMode,

        [ValidateSet('preserve', 'captureDate')]
        [string]$FileTimestampMode = 'preserve',

        [string]$FileTimestampOffset = '+00:00',

        [ValidateSet('HEVC', 'AV1')]
        [string]$ExpectedOutputCodec = 'HEVC'
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        $errors.Add("Output file does not exist: $OutputFile")
    } else {
        $file = Get-Item -LiteralPath $OutputFile
        if ($file.Length -le 0) {
            $errors.Add('Output file size is zero')
        }
    }

    if ($SourceInfo.Width -ne $OutputInfo.Width -or $SourceInfo.Height -ne $OutputInfo.Height) {
        $errors.Add("Resolution mismatch: $($SourceInfo.Width)x$($SourceInfo.Height) -> $($OutputInfo.Width)x$($OutputInfo.Height)")
    }

    if ($null -ne $SourceInfo.Rotation -or $null -ne $OutputInfo.Rotation) {
        if ($null -eq $SourceInfo.Rotation -or $null -eq $OutputInfo.Rotation -or [math]::Abs($SourceInfo.Rotation - $OutputInfo.Rotation) -gt $RotationTolerance) {
            $errors.Add("Rotation mismatch: $($SourceInfo.Rotation) -> $($OutputInfo.Rotation)")
        }
    }

    if ($null -ne $SourceInfo.Fps -and $null -ne $OutputInfo.Fps) {
        if ([math]::Abs($SourceInfo.Fps - $OutputInfo.Fps) -gt $FpsTolerance) {
            $errors.Add("FPS mismatch: $($SourceInfo.Fps) -> $($OutputInfo.Fps)")
        }
    }

    if ($null -ne $SourceInfo.BitDepth -and $null -ne $OutputInfo.BitDepth -and $SourceInfo.BitDepth -ne $OutputInfo.BitDepth -and -not $SourceInfo.IsHdr) {
        $errors.Add("BitDepth mismatch: $($SourceInfo.BitDepth) -> $($OutputInfo.BitDepth)")
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Transfer) -and -not $SourceInfo.IsHdr) {
        if (-not (Test-StringEquivalentNormalized -Actual $OutputInfo.Transfer -Expected $SourceInfo.Transfer)) {
            $errors.Add("Transfer mismatch: '$($SourceInfo.Transfer)' -> '$($OutputInfo.Transfer)'")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Primaries) -and -not $SourceInfo.IsHdr) {
        if (-not (Test-StringEquivalentNormalized -Actual $OutputInfo.Primaries -Expected $SourceInfo.Primaries)) {
            $errors.Add("Primaries mismatch: '$($SourceInfo.Primaries)' -> '$($OutputInfo.Primaries)'")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Matrix)) {
        if (-not (Test-StringEquivalentNormalized -Actual $OutputInfo.Matrix -Expected $SourceInfo.Matrix)) {
            $errors.Add("Matrix mismatch: '$($SourceInfo.Matrix)' -> '$($OutputInfo.Matrix)'")
        }
    }

    if (-not $SourceInfo.IsHdr -and $OutputInfo.BitDepth -ne 8) {
        $errors.Add("SDR output bit depth must be 8-bit, got $($OutputInfo.BitDepth)")
    }

    if ($OutputInfo.Codec -ne $ExpectedOutputCodec) {
        $errors.Add("Output codec must be $ExpectedOutputCodec, got $($OutputInfo.Codec)")
    }

    if ($SourceInfo.AudioTrackCount -ne $OutputInfo.AudioTrackCount) {
        $errors.Add("Audio track count mismatch: $($SourceInfo.AudioTrackCount) -> $($OutputInfo.AudioTrackCount)")
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.AudioCodec) -and [string]::IsNullOrWhiteSpace($OutputInfo.AudioCodec)) {
        $errors.Add('Audio codec missing in output')
    }

    $sourceAudioTracks = @($SourceInfo.AudioTracks)
    $outputAudioTracks = @($OutputInfo.AudioTracks)
    if ($sourceAudioTracks.Count -gt 0 -or $outputAudioTracks.Count -gt 0) {
        $trackCount = [math]::Min($sourceAudioTracks.Count, $outputAudioTracks.Count)
        for ($index = 0; $index -lt $trackCount; $index++) {
            if (-not (Test-StringEquivalentNormalized -Actual $outputAudioTracks[$index].Codec -Expected $sourceAudioTracks[$index].Codec)) {
                $errors.Add("Audio codec mismatch on track $($index + 1): '$($sourceAudioTracks[$index].Codec)' -> '$($outputAudioTracks[$index].Codec)'")
            }

            if ($null -ne $sourceAudioTracks[$index].Channels -or $null -ne $outputAudioTracks[$index].Channels) {
                if ($sourceAudioTracks[$index].Channels -ne $outputAudioTracks[$index].Channels) {
                    $errors.Add("Audio channels mismatch on track $($index + 1): $($sourceAudioTracks[$index].Channels) -> $($outputAudioTracks[$index].Channels)")
                }
            }
        }
    }

    $hdrValidation = Test-HdrCompatibility -SourceInfo $SourceInfo -OutputInfo $OutputInfo
    foreach ($warning in $hdrValidation.Warnings) {
        $warnings.Add($warning)
    }
    foreach ($error in $hdrValidation.Errors) {
        $errors.Add($error)
    }

    if ($ValidateTimestamps) {
        $expectedTimestamp = $null
        if ($FileTimestampMode -eq 'captureDate' -and $null -ne $CaptureDateResult -and $CaptureDateResult.Success -and $null -ne $CaptureDateResult.DateTime) {
            $expectedTimestamp = $CaptureDateResult.DateTime
            if ($CaptureDateResult.Source -eq 'Metadata') {
                $expectedTimestamp = ConvertTo-TimezoneAdjustedDate -DateTime $expectedTimestamp -Offset $FileTimestampOffset
            }
        }

        $timestampValidation = Test-FileTimestampsPreserved -SourceFile $SourceFile -OutputFile $OutputFile -ExpectedCreationTime $expectedTimestamp -ExpectedLastWriteTime $expectedTimestamp -ExpectedLastAccessTime $expectedTimestamp
        foreach ($timestampError in @($timestampValidation.Errors)) {
            $errors.Add($timestampError)
        }
        foreach ($timestampWarning in @($timestampValidation.Warnings)) {
            $warnings.Add($timestampWarning)
        }
    }

    foreach ($metadataError in (Test-MetadataPreserved -SourceMetadata $SourceMetadata -OutputMetadata $OutputMetadata)) {
        $errors.Add($metadataError)
    }

    $captureDateValidation = Test-CaptureDateValidation -CaptureDateResult $CaptureDateResult -OutputMetadata $OutputMetadata -StrictDateMode:$StrictDateMode
    foreach ($warning in $captureDateValidation.Warnings) {
        $warnings.Add($warning)
    }
    foreach ($error in $captureDateValidation.Errors) {
        $errors.Add($error)
    }

    [pscustomobject]@{
        Success = ($errors.Count -eq 0)
        Warnings = @($warnings)
        Errors = @($errors)
    }
}

Export-ModuleMember -Function Test-EncodedVideo, Test-FileTimestampsPreserved, Test-MetadataPreserved
