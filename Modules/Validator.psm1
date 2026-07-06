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

function Test-FileTimestampsPreserved {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$OutputFile
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

    if ($source.LastAccessTime -ne $output.LastAccessTime) {
        $errors.Add("LastAccessTime mismatch: $($source.LastAccessTime) -> $($output.LastAccessTime)")
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

        [switch]$ValidateTimestamps
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

    if ($null -ne $SourceInfo.Fps -and $null -ne $OutputInfo.Fps) {
        if ([math]::Abs($SourceInfo.Fps - $OutputInfo.Fps) -gt 0.01) {
            $errors.Add("FPS mismatch: $($SourceInfo.Fps) -> $($OutputInfo.Fps)")
        }
    }

    if ($SourceInfo.IsHdr -and -not $OutputInfo.IsHdr) {
        $errors.Add('HDR source became SDR')
    }

    if ($SourceInfo.IsHdr -and $OutputInfo.BitDepth -ne 10) {
        $errors.Add("HDR output bit depth must be 10-bit, got $($OutputInfo.BitDepth)")
    }

    if ($SourceInfo.IsHdr) {
        if (-not (Test-StringContainsNormalized -Actual $OutputInfo.Transfer -Expected $SourceInfo.Transfer)) {
            $errors.Add("HDR transfer mismatch: '$($SourceInfo.Transfer)' -> '$($OutputInfo.Transfer)'")
        }

        if (-not (Test-StringContainsNormalized -Actual $OutputInfo.Primaries -Expected $SourceInfo.Primaries)) {
            $errors.Add("HDR primaries mismatch: '$($SourceInfo.Primaries)' -> '$($OutputInfo.Primaries)'")
        }

        if (-not (Test-StringContainsNormalized -Actual $OutputInfo.Matrix -Expected $SourceInfo.Matrix)) {
            $errors.Add("HDR matrix mismatch: '$($SourceInfo.Matrix)' -> '$($OutputInfo.Matrix)'")
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

    if ($ValidateTimestamps) {
        foreach ($timestampError in (Test-FileTimestampsPreserved -SourceFile $SourceFile -OutputFile $OutputFile)) {
            $errors.Add($timestampError)
        }
    }

    [pscustomobject]@{
        Success = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

Export-ModuleMember -Function Test-EncodedVideo, Test-FileTimestampsPreserved
