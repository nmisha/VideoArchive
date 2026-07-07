Set-StrictMode -Version Latest

function Get-ExifToolValue {
    param(
        [Parameter(Mandatory)]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return $property.Value
        }
    }

    return $null
}

function ConvertTo-NullableExifDouble {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $normalized = ([string]$Value -replace ',', '.')
    $match = [regex]::Match($normalized, '-?\d+(?:\.\d+)?')
    if (-not $match.Success) {
        return $null
    }

    return [double]::Parse($match.Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-NormalizedMetadataDate {
    param($Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }

    $text = ([string]$Value).Trim()
    if ($text -match '^\d{4}:\d{2}:\d{2}\s+\d{2}:\d{2}:\d{2}$') {
        $text = $text -replace '^(\d{4}):(\d{2}):(\d{2})\s+', '$1-$2-$3T'
    } elseif ($text -match '^\d{4}:\d{2}:\d{2}\s+\d{2}:\d{2}:\d{2}.*$') {
        $text = $text -replace '^(\d{4}):(\d{2}):(\d{2})\s+', '$1-$2-$3T'
    }

    try {
        return ([datetime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-ddTHH:mm:ss')
    } catch {
    }

    return $text
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

function ConvertFrom-ExifToolJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExifToolJson,

        [string]$Path
    )

    $parsed = $ExifToolJson | ConvertFrom-Json
    if ($null -eq $parsed) {
        throw "ExifTool JSON does not contain metadata for '$Path'."
    }

    $item = if ($parsed -is [System.Array]) { $parsed[0] } else { $parsed }
    $gpsLatitude = ConvertTo-NullableExifDouble (Get-ExifToolValue -Object $item -Names @('GPSLatitude', 'Composite:GPSLatitude'))
    $gpsLongitude = ConvertTo-NullableExifDouble (Get-ExifToolValue -Object $item -Names @('GPSLongitude', 'Composite:GPSLongitude'))
    $quickTimeMediaCreateDate = ConvertTo-NormalizedMetadataDate (Get-ExifToolValue -Object $item -Names @('QuickTime:MediaCreateDate', 'MediaCreateDate'))
    $quickTimeCreateDate = ConvertTo-NormalizedMetadataDate (Get-ExifToolValue -Object $item -Names @('QuickTime:CreateDate', 'CreateDate'))
    $quickTimeTrackCreateDate = ConvertTo-NormalizedMetadataDate (Get-ExifToolValue -Object $item -Names @('QuickTime:TrackCreateDate', 'TrackCreateDate'))
    $exifDateTimeOriginal = ConvertTo-NormalizedMetadataDate (Get-ExifToolValue -Object $item -Names @('EXIF:DateTimeOriginal', 'DateTimeOriginal'))
    $xmpCreateDate = ConvertTo-NormalizedMetadataDate (Get-ExifToolValue -Object $item -Names @('XMP:CreateDate'))
    $keysCreationDate = ConvertTo-NormalizedMetadataDate (Get-ExifToolValue -Object $item -Names @('Keys:CreationDate', 'CreationDate'))
    $dateTaken = $exifDateTimeOriginal
    if ([string]::IsNullOrWhiteSpace($dateTaken)) { $dateTaken = $quickTimeMediaCreateDate }
    if ([string]::IsNullOrWhiteSpace($dateTaken)) { $dateTaken = $quickTimeCreateDate }
    if ([string]::IsNullOrWhiteSpace($dateTaken)) { $dateTaken = $quickTimeTrackCreateDate }
    if ([string]::IsNullOrWhiteSpace($dateTaken)) { $dateTaken = $xmpCreateDate }
    if ([string]::IsNullOrWhiteSpace($dateTaken)) { $dateTaken = $keysCreationDate }

    [pscustomobject]@{
        Path = $Path
        DateTaken = $dateTaken
        QuickTimeMediaCreateDate = $quickTimeMediaCreateDate
        QuickTimeCreateDate = $quickTimeCreateDate
        QuickTimeTrackCreateDate = $quickTimeTrackCreateDate
        ExifDateTimeOriginal = $exifDateTimeOriginal
        XmpCreateDate = $xmpCreateDate
        KeysCreationDate = $keysCreationDate
        GpsLatitude = $gpsLatitude
        GpsLongitude = $gpsLongitude
        HasGps = ($null -ne $gpsLatitude -and $null -ne $gpsLongitude)
    }
}

function Set-FileSystemTimestamps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$DestinationFile,

        [ValidateSet('preserve', 'captureDate')]
        [string]$FileTimestampMode = 'captureDate',

        [Nullable[datetime]]$CaptureDate,

        [string]$CaptureDateSource = 'None',

        [string]$CaptureDateOffset = '+00:00'
    )

    $source = Get-Item -LiteralPath $SourceFile
    $destination = Get-Item -LiteralPath $DestinationFile

    if ($FileTimestampMode -eq 'captureDate' -and $null -ne $CaptureDate) {
        $targetDate = $CaptureDate
        if ($CaptureDateSource -eq 'Metadata') {
            $targetDate = ConvertTo-TimezoneAdjustedDate -DateTime $CaptureDate -Offset $CaptureDateOffset
        }

        $destination.CreationTime = $targetDate
        $destination.LastWriteTime = $targetDate
        $destination.LastAccessTime = $targetDate
        return
    }

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

        [switch]$PreserveWindowsTimestamps,

        [ValidateSet('preserve', 'captureDate')]
        [string]$FileTimestampMode = 'captureDate',

        [Nullable[datetime]]$CaptureDate,

        [string]$CaptureDateSource = 'None',

        [string]$CaptureDateOffset = '+00:00'
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

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $ExifToolPath @args 2>&1 | ForEach-Object { $_.ToString() } | Out-String
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "ExifTool failed for '$DestinationFile': $output"
    }

    if ($PreserveWindowsTimestamps) {
        Set-FileSystemTimestamps -SourceFile $SourceFile -DestinationFile $DestinationFile -FileTimestampMode $FileTimestampMode -CaptureDate $CaptureDate -CaptureDateSource $CaptureDateSource -CaptureDateOffset $CaptureDateOffset
    }

    return $output.Trim()
}
function Get-VideoMetadataSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExifToolPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Metadata file not found: $Path"
    }

    $args = @(
        '-j'
        '-n'
        '-DateTimeOriginal'
        '-CreateDate'
        '-QuickTime:MediaCreateDate'
        '-QuickTime:CreateDate'
        '-QuickTime:TrackCreateDate'
        '-MediaCreateDate'
        '-TrackCreateDate'
        '-ContentCreateDate'
        '-XMP:CreateDate'
        '-Keys:CreationDate'
        '-CreationDate'
        '-GPSLatitude'
        '-GPSLongitude'
        $Path
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $ExifToolPath @args 2>&1 | ForEach-Object { $_.ToString() } | Out-String
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "ExifTool metadata read failed for '$Path': $output"
    }

    return ConvertFrom-ExifToolJson -ExifToolJson $output -Path $Path
}

Export-ModuleMember -Function Copy-VideoMetadata, ConvertFrom-ExifToolJson, Get-VideoMetadataSnapshot
