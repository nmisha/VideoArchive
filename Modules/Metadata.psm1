Set-StrictMode -Version Latest

function Set-FileSystemTimestamps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$DestinationFile
    )

    $source = Get-Item -LiteralPath $SourceFile
    $destination = Get-Item -LiteralPath $DestinationFile
    $destination.CreationTime = $source.CreationTime
    $destination.LastWriteTime = $source.LastWriteTime
    $destination.LastAccessTime = $source.LastAccessTime
}

function Copy-VideoMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$DestinationFile,

        [Parameter(Mandatory)]
        [string]$ExifToolPath,

        [switch]$PreserveWindowsTimestamps
    )

    if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
        throw "Metadata source file not found: $SourceFile"
    }

    if (-not (Test-Path -LiteralPath $DestinationFile -PathType Leaf)) {
        throw "Metadata destination file not found: $DestinationFile"
    }

    $args = @(
        '-overwrite_original'
        '-TagsFromFile', $SourceFile
        '-All:All'
        '-Keys:All'
        '-XMP:All'
        '-FileCreateDate'
        '-FileModifyDate'
        $DestinationFile
    )

    $output = & $ExifToolPath @args 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "ExifTool failed for '$DestinationFile': $output"
    }

    if ($PreserveWindowsTimestamps) {
        Set-FileSystemTimestamps -SourceFile $SourceFile -DestinationFile $DestinationFile
    }

    return $output.Trim()
}

Export-ModuleMember -Function Copy-VideoMetadata
