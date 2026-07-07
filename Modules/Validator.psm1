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

function Test-FileTimestampsPreserved {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$OutputFile,

        [double]$LastAccessToleranceSeconds = 2
    )

    $source = Get-Item -LiteralPath $SourceFile
    $output = Get-Item -LiteralPath $OutputFile
    $errors = New-Object System.Collections.Generic.List[string]

    if ($source.CreationTime -ne $output.CreationTime) {
        $errors.Add("CreationTime mismatch: $($source.CreationTime) -> $($output.CreationTime)")
    }

    if ($source.LastWriteTime -ne $output.LastWriteTime) {
        $errors.Add("LastWriteTime mismatch: $($source.LastWriteTime) -> $($output.LastWriteTime)")
    }

    $lastAccessDelta = [math]::Abs(($source.LastAccessTime - $output.LastAccessTime).TotalSeconds)
    if ($lastAccessDelta -gt $LastAccessToleranceSeconds) {
        $errors.Add("LastAccessTime mismatch: $($source.LastAccessTime) -> $($output.LastAccessTime) (delta ${lastAccessDelta}s)")
    }

    return @($errors)
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

        [double]$FpsTolerance = 0.05,

        [double]$RotationTolerance = 0.1,

        [psobject]$SourceMetadata,

        [psobject]$OutputMetadata
    )

    $errors = New-Object System.Collections.Generic.List[string]

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

    if ($SourceInfo.IsHdr -and -not $OutputInfo.IsHdr) {
        $errors.Add('HDR source became SDR')
    }

    if ($null -ne $SourceInfo.BitDepth -and $null -ne $OutputInfo.BitDepth -and $SourceInfo.BitDepth -ne $OutputInfo.BitDepth) {
        $errors.Add("BitDepth mismatch: $($SourceInfo.BitDepth) -> $($OutputInfo.BitDepth)")
    }

    if ($SourceInfo.IsHdr -and $OutputInfo.BitDepth -ne 10) {
        $errors.Add("HDR output bit depth must be 10-bit, got $($OutputInfo.BitDepth)")
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Transfer)) {
        if (-not (Test-StringEquivalentNormalized -Actual $OutputInfo.Transfer -Expected $SourceInfo.Transfer)) {
            $errors.Add("Transfer mismatch: '$($SourceInfo.Transfer)' -> '$($OutputInfo.Transfer)'")
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SourceInfo.Primaries)) {
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

    if ($OutputInfo.Codec -ne 'HEVC') {
        $errors.Add("Output codec must be HEVC, got $($OutputInfo.Codec)")
    }

    if ($SourceInfo.AudioTrackCount -ne $OutputInfo.AudioTrackCount) {
        $errors.Add("Audio track count mismatch: $($SourceInfo.AudioTrackCount) -> $($OutputInfo.AudioTrackCount)")
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

    if ($ValidateTimestamps) {
        foreach ($timestampError in (Test-FileTimestampsPreserved -SourceFile $SourceFile -OutputFile $OutputFile)) {
            $errors.Add($timestampError)
        }
    }

    foreach ($metadataError in (Test-MetadataPreserved -SourceMetadata $SourceMetadata -OutputMetadata $OutputMetadata)) {
        $errors.Add($metadataError)
    }

    [pscustomobject]@{
        Success = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

Export-ModuleMember -Function Test-EncodedVideo, Test-FileTimestampsPreserved, Test-MetadataPreserved
