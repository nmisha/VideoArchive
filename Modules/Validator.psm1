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

function Resolve-ComparableColorValue {
    [CmdletBinding()]
    param(
        [string]$Actual,
        [string]$Expected,
        [bool]$IsHdr
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $resolvedActual = $Actual

    if (-not $IsHdr -and [string]::IsNullOrWhiteSpace($Actual) -and -not [string]::IsNullOrWhiteSpace($Expected)) {
        $normalizedExpected = ($Expected -replace '\s+', '').ToLowerInvariant()
        if ($normalizedExpected -eq 'bt.709' -or $normalizedExpected -eq 'bt709') {
            $resolvedActual = $Expected
            $warnings.Add("Output color tag missing; assumed '$Expected' for SDR compatibility")
        }
    }

    [pscustomobject]@{
        Actual = $resolvedActual
        Warnings = @($warnings)
    }
}

function Test-MetadataDateEquivalent {
    param([string]$Actual, [string]$Expected)

    if ([string]::IsNullOrWhiteSpace($Actual) -or [string]::IsNullOrWhiteSpace($Expected)) { return $false }
    $offsetPattern = '(?:Z|[+\-]\d{2}:?\d{2})$'
    try {
        if ($Actual -match $offsetPattern -and $Expected -match $offsetPattern) {
            $actualDate = [datetimeoffset]::Parse($Actual, [Globalization.CultureInfo]::InvariantCulture)
            $expectedDate = [datetimeoffset]::Parse($Expected, [Globalization.CultureInfo]::InvariantCulture)
            return [math]::Abs(($actualDate.UtcDateTime - $expectedDate.UtcDateTime).TotalSeconds) -le 1
        }
        # An unknown timezone cannot be inferred from the machine timezone.
        # Compare wall clocks here; Test-CaptureDateValidation checks the
        # resolved offset separately when one is available.
        $actualDate = [datetime]::Parse(($Actual -replace $offsetPattern, ''), [Globalization.CultureInfo]::InvariantCulture)
        $expectedDate = [datetime]::Parse(($Expected -replace $offsetPattern, ''), [Globalization.CultureInfo]::InvariantCulture)
        return [math]::Abs(($actualDate - $expectedDate).TotalSeconds) -le 1
    } catch { return $false }
}

function Test-MetadataPreserved {
    [CmdletBinding()]
    param(
        [psobject]$SourceMetadata,

        [psobject]$OutputMetadata,

        [switch]$AllowMissingDateTaken,

        [switch]$AllowMissingGps,

        [double]$GpsTolerance = 0.0001
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if ($null -eq $SourceMetadata -or $null -eq $OutputMetadata) {
        return @($errors)
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$SourceMetadata.DateTaken)) {
        if (-not (Test-MetadataDateEquivalent -Actual $OutputMetadata.DateTaken -Expected $SourceMetadata.DateTaken)) {
            $dateTakenIsMissing = [string]::IsNullOrWhiteSpace([string]$OutputMetadata.DateTaken)
            if (-not ($AllowMissingDateTaken -and $dateTakenIsMissing)) {
                $errors.Add("DateTaken mismatch: '$($SourceMetadata.DateTaken)' -> '$($OutputMetadata.DateTaken)'")
            }
        }
    }

    if ($SourceMetadata.HasGps) {
        if (-not $OutputMetadata.HasGps) {
            if (-not $AllowMissingGps) {
                $errors.Add('GPS metadata missing in output')
            }
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

function Get-OptionalObjectValue {
    param([psobject]$Object, [string]$Name)

    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-MetadataSidecar {
    [CmdletBinding()]
    param(
        [string]$SidecarPath,
        [Parameter(Mandatory)][string]$SourceFile,
        [Parameter(Mandatory)][string]$OutputFile,
        [psobject]$CaptureDateResult,
        [psobject]$SourceMetadata,
        [double]$DateToleranceSeconds = 2,
        [double]$GpsTolerance = 0.0001
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($SidecarPath) -or -not (Test-Path -LiteralPath $SidecarPath -PathType Leaf)) {
        $errors.Add("MKV metadata sidecar is missing: $SidecarPath")
        return [pscustomobject]@{ Success = $false; Errors = @($errors); Warnings = @($warnings) }
    }

    try {
        $sidecar = Get-Content -LiteralPath $SidecarPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $errors.Add("MKV metadata sidecar is invalid JSON: $($_.Exception.Message)")
        return [pscustomobject]@{ Success = $false; Errors = @($errors); Warnings = @($warnings) }
    }

    if ([int]$sidecar.SchemaVersion -ne 1) {
        $errors.Add("Unsupported metadata sidecar schema version: $($sidecar.SchemaVersion)")
    }

    $expectedSource = [System.IO.Path]::GetFullPath($SourceFile)
    $expectedOutput = [System.IO.Path]::GetFullPath($OutputFile)
    $sourceItem = Get-Item -LiteralPath $SourceFile -ErrorAction Stop
    if (-not [string]::Equals([string]$sidecar.SourceFile, $expectedSource, [System.StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add("Metadata sidecar source mismatch: '$($sidecar.SourceFile)' -> '$expectedSource'")
    }
    if (-not [string]::Equals([string]$sidecar.OutputFile, $expectedOutput, [System.StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add("Metadata sidecar output mismatch: '$($sidecar.OutputFile)' -> '$expectedOutput'")
    }
    if ([long]$sidecar.SourceFileSizeBytes -ne [long]$sourceItem.Length) {
        $errors.Add("Metadata sidecar source size mismatch: '$($sidecar.SourceFileSizeBytes)' -> '$($sourceItem.Length)'")
    }
    try {
        $sidecarLastWriteUtc = [datetime]::Parse([string]$sidecar.SourceLastWriteTimeUtc, [System.Globalization.CultureInfo]::InvariantCulture).ToUniversalTime()
        if ([math]::Abs(($sourceItem.LastWriteTimeUtc - $sidecarLastWriteUtc).TotalSeconds) -gt 1) {
            $errors.Add('Metadata sidecar source timestamp fingerprint does not match the source file')
        }
    } catch {
        $errors.Add("Metadata sidecar source timestamp is missing or invalid: '$($sidecar.SourceLastWriteTimeUtc)'")
    }

    if ($null -ne $CaptureDateResult -and $CaptureDateResult.Success) {
        if ([string]$sidecar.CaptureDateSource -ne [string]$CaptureDateResult.Source) {
            $errors.Add("Metadata sidecar capture date source mismatch: '$($sidecar.CaptureDateSource)' -> '$($CaptureDateResult.Source)'")
        }
        if ([string]$sidecar.CaptureDatePattern -ne [string]$CaptureDateResult.Pattern) {
            $errors.Add("Metadata sidecar capture date pattern mismatch: '$($sidecar.CaptureDatePattern)' -> '$($CaptureDateResult.Pattern)'")
        }
        try {
            $sidecarDate = [datetime]::Parse([string]$sidecar.CaptureDate, [System.Globalization.CultureInfo]::InvariantCulture)
            if ([math]::Abs(($CaptureDateResult.DateTime - $sidecarDate).TotalSeconds) -gt $DateToleranceSeconds) {
                $errors.Add("Metadata sidecar capture date mismatch: '$($CaptureDateResult.DateTime)' -> '$($sidecar.CaptureDate)'")
            }
        } catch {
            $errors.Add("Metadata sidecar capture date is missing or invalid: '$($sidecar.CaptureDate)'")
        }
    }

    if ($null -ne $SourceMetadata -and $SourceMetadata.HasGps) {
        if ($null -eq $sidecar.GpsLatitude -or $null -eq $sidecar.GpsLongitude) {
            $errors.Add('GPS metadata missing in MKV sidecar')
        } else {
            $latitudeDelta = [math]::Abs(([double]$SourceMetadata.GpsLatitude) - ([double]$sidecar.GpsLatitude))
            $longitudeDelta = [math]::Abs(([double]$SourceMetadata.GpsLongitude) - ([double]$sidecar.GpsLongitude))
            if ($latitudeDelta -gt $GpsTolerance -or $longitudeDelta -gt $GpsTolerance) {
                $errors.Add('GPS metadata mismatch in MKV sidecar')
            }
        }
    }

    return [pscustomobject]@{ Success = ($errors.Count -eq 0); Errors = @($errors); Warnings = @($warnings) }
}

function Test-CaptureDateValidation {
    [CmdletBinding()]
    param(
        [psobject]$CaptureDateResult,

        [psobject]$OutputMetadata,

        [bool]$StrictDateMode,

        [switch]$AllowMissingOutputDateTags,

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

    $quickTimeDates = @(@(
        Get-OptionalObjectValue -Object $OutputMetadata -Name 'QuickTimeMediaCreateDate'
        Get-OptionalObjectValue -Object $OutputMetadata -Name 'QuickTimeCreateDate'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $localDates = @(@(
        Get-OptionalObjectValue -Object $OutputMetadata -Name 'KeysCreationDate'
        Get-OptionalObjectValue -Object $OutputMetadata -Name 'XmpCreateDate'
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $hasTimezone = $null -ne $CaptureDateResult.PSObject.Properties['HasTimezone'] -and [bool]$CaptureDateResult.HasTimezone
    $candidateDates = @()
    if ($hasTimezone) {
        $candidateDates += @($localDates)
    } else {
        $candidateDates += @($localDates)
        $candidateDates += @($quickTimeDates)
    }

    if (@($candidateDates).Count -eq 0) {
        if ($AllowMissingOutputDateTags) {
            $warnings.Add('Output container does not support writable embedded capture-date tags; capture date is preserved in the validated metadata sidecar.')
        } else {
            $errors.Add('Output capture date tags are missing.')
        }
        return [pscustomobject]@{
            Warnings = @($warnings)
            Errors = @($errors)
        }
    }

    $expected = $CaptureDateResult.DateTime
    $matched = $false
    foreach ($candidateDate in $candidateDates) {
        try {
            if ($hasTimezone -and [string]$candidateDate -match '(?:Z|[+\-]\d{2}:?\d{2})$') {
                $actualWithOffset = [datetimeoffset]::Parse([string]$candidateDate, [System.Globalization.CultureInfo]::InvariantCulture)
                $expectedWithOffset = [datetimeoffset]$CaptureDateResult.DateTimeOffset
                if ([math]::Abs(($expectedWithOffset.UtcDateTime - $actualWithOffset.UtcDateTime).TotalSeconds) -le $ToleranceSeconds -and $expectedWithOffset.Offset -eq $actualWithOffset.Offset) {
                    $matched = $true
                    break
                }
            } else {
                $actual = [datetime]::Parse([string]$candidateDate, [System.Globalization.CultureInfo]::InvariantCulture)
                if ([math]::Abs(($expected - $actual).TotalSeconds) -le $ToleranceSeconds) {
                    $matched = $true
                    break
                }
            }
        } catch {
        }
    }

    if ($matched -and $hasTimezone -and $quickTimeDates.Count -gt 0) {
        $expectedUtc = ([datetimeoffset]$CaptureDateResult.DateTimeOffset).UtcDateTime
        $utcMatched = $false
        foreach ($quickTimeDate in $quickTimeDates) {
            try {
                $actualUtc = [datetime]::SpecifyKind([datetime]::Parse([string]$quickTimeDate, [System.Globalization.CultureInfo]::InvariantCulture), [DateTimeKind]::Utc)
                if ([math]::Abs(($expectedUtc - $actualUtc).TotalSeconds) -le $ToleranceSeconds) {
                    $utcMatched = $true
                    break
                }
            } catch { }
        }
        if (-not $utcMatched) {
            $matched = $false
            $errors.Add("QuickTime UTC date mismatch: expected $($expectedUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'))")
        }
    }

    if (-not $matched -and $errors.Count -eq 0) {
        $expectedText = if ($hasTimezone) { ([datetimeoffset]$CaptureDateResult.DateTimeOffset).ToString('yyyy-MM-ddTHH:mm:sszzz') } else { $expected.ToString('yyyy-MM-ddTHH:mm:ss') }
        $errors.Add("Capture date mismatch: expected $expectedText")
    }

    return [pscustomobject]@{
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

        [string]$ExpectedOutputCodec = 'HEVC',

        [ValidateSet('copy', 'aac')]
        [string]$ExpectedAudioMode = 'copy',

        [string]$SidecarPath,

        [ValidateSet('none', 'metadata', 'physical')]
        [string]$RotationMode = 'none',

        [ValidateSet(0, 90, 180, 270)]
        [int]$AppliedRotation = 0
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

    $sourceRotation = if ($null -eq $SourceInfo.Rotation) { 0.0 } else { [double]$SourceInfo.Rotation }
    $outputRotation = if ($null -eq $OutputInfo.Rotation) { 0.0 } else { [double]$OutputInfo.Rotation }
    $normalizedSourceRotation = (($sourceRotation % 360.0) + 360.0) % 360.0
    $expectedWidth = $SourceInfo.Width
    $expectedHeight = $SourceInfo.Height
    $expectedRotation = $normalizedSourceRotation
    if ($RotationMode -eq 'physical') {
        if ($AppliedRotation -in @(90, 270)) {
            $expectedWidth = $SourceInfo.Height
            $expectedHeight = $SourceInfo.Width
        }
        $expectedRotation = 0.0
    } elseif ($RotationMode -eq 'metadata') {
        $expectedRotation = $AppliedRotation
    }

    if ($expectedWidth -ne $OutputInfo.Width -or $expectedHeight -ne $OutputInfo.Height) {
        $errors.Add("Resolution mismatch: expected ${expectedWidth}x${expectedHeight}, got $($OutputInfo.Width)x$($OutputInfo.Height)")
    }

    $normalizedOutputRotation = (($outputRotation % 360.0) + 360.0) % 360.0
    $rotationDifference = [math]::Abs($expectedRotation - $normalizedOutputRotation)
    $rotationDifference = [math]::Min($rotationDifference, 360.0 - $rotationDifference)
    if ($rotationDifference -gt $RotationTolerance) {
        $errors.Add("Rotation mismatch: expected $expectedRotation, got $normalizedOutputRotation")
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
        $transferComparison = Resolve-ComparableColorValue -Actual $OutputInfo.Transfer -Expected $SourceInfo.Transfer -IsHdr:$SourceInfo.IsHdr
        foreach ($warning in @($transferComparison.Warnings)) {
            $warnings.Add($warning)
        }

        if (-not (Test-StringEquivalentNormalized -Actual $transferComparison.Actual -Expected $SourceInfo.Transfer)) {
            $errors.Add("Transfer mismatch: '$($SourceInfo.Transfer)' -> '$($OutputInfo.Transfer)'")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Primaries) -and -not $SourceInfo.IsHdr) {
        $primariesComparison = Resolve-ComparableColorValue -Actual $OutputInfo.Primaries -Expected $SourceInfo.Primaries -IsHdr:$SourceInfo.IsHdr
        foreach ($warning in @($primariesComparison.Warnings)) {
            $warnings.Add($warning)
        }

        if (-not (Test-StringEquivalentNormalized -Actual $primariesComparison.Actual -Expected $SourceInfo.Primaries)) {
            $errors.Add("Primaries mismatch: '$($SourceInfo.Primaries)' -> '$($OutputInfo.Primaries)'")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Matrix)) {
        $matrixComparison = Resolve-ComparableColorValue -Actual $OutputInfo.Matrix -Expected $SourceInfo.Matrix -IsHdr:$SourceInfo.IsHdr
        foreach ($warning in @($matrixComparison.Warnings)) {
            $warnings.Add($warning)
        }

        if (-not (Test-StringEquivalentNormalized -Actual $matrixComparison.Actual -Expected $SourceInfo.Matrix)) {
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
            $expectedAudioCodec = if ($ExpectedAudioMode -eq 'aac') { 'AAC' } else { [string]$sourceAudioTracks[$index].Codec }
            if (-not (Test-StringEquivalentNormalized -Actual $outputAudioTracks[$index].Codec -Expected $expectedAudioCodec)) {
                $errors.Add("Audio codec mismatch on track $($index + 1): expected '$expectedAudioCodec', got '$($outputAudioTracks[$index].Codec)' (source '$($sourceAudioTracks[$index].Codec)')")
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
            $hasCaptureTimezone = $null -ne $CaptureDateResult.PSObject.Properties['HasTimezone'] -and [bool]$CaptureDateResult.HasTimezone
            if ($hasCaptureTimezone) {
                $expectedTimestamp = ([datetimeoffset]$CaptureDateResult.DateTimeOffset).UtcDateTime.ToLocalTime()
            } else {
                $expectedTimestamp = [datetime]::SpecifyKind($CaptureDateResult.DateTime, [DateTimeKind]::Unspecified)
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

    $outputExtension = [System.IO.Path]::GetExtension($OutputFile).ToLowerInvariant()
    $sidecarValidation = $null
    if ($outputExtension -eq '.mkv') {
        $sidecarValidation = Test-MetadataSidecar -SidecarPath $SidecarPath -SourceFile $SourceFile -OutputFile $OutputFile -CaptureDateResult $CaptureDateResult -SourceMetadata $SourceMetadata
        foreach ($sidecarWarning in @($sidecarValidation.Warnings)) { $warnings.Add($sidecarWarning) }
        foreach ($sidecarError in @($sidecarValidation.Errors)) { $errors.Add($sidecarError) }
    }
    $allowMissingEmbeddedDate = ($outputExtension -eq '.mkv' -and $null -ne $sidecarValidation -and $sidecarValidation.Success)

    foreach ($metadataError in (Test-MetadataPreserved -SourceMetadata $SourceMetadata -OutputMetadata $OutputMetadata -AllowMissingDateTaken:$allowMissingEmbeddedDate -AllowMissingGps:$allowMissingEmbeddedDate)) {
        $errors.Add($metadataError)
    }

    $captureDateValidation = Test-CaptureDateValidation -CaptureDateResult $CaptureDateResult -OutputMetadata $OutputMetadata -StrictDateMode:$StrictDateMode -AllowMissingOutputDateTags:$allowMissingEmbeddedDate
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

Export-ModuleMember -Function Test-EncodedVideo, Test-FileTimestampsPreserved, Test-MetadataPreserved, Test-MetadataSidecar
