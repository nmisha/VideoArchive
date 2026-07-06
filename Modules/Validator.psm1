Set-StrictMode -Version Latest

function Test-EncodedVideo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$SourceInfo,

        [Parameter(Mandatory)]
        [psobject]$OutputInfo,

        [Parameter(Mandatory)]
        [string]$OutputFile
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

    if (-not $SourceInfo.IsHdr -and $OutputInfo.BitDepth -ne 8) {
        $errors.Add("SDR output bit depth must be 8-bit, got $($OutputInfo.BitDepth)")
    }

    if ($OutputInfo.Codec -ne 'HEVC') {
        $errors.Add("Output codec must be HEVC, got $($OutputInfo.Codec)")
    }

    if ($SourceInfo.AudioTrackCount -ne $OutputInfo.AudioTrackCount) {
        $errors.Add("Audio track count mismatch: $($SourceInfo.AudioTrackCount) -> $($OutputInfo.AudioTrackCount)")
    }

    [pscustomobject]@{
        Success = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

Export-ModuleMember -Function Test-EncodedVideo
