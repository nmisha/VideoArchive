Set-StrictMode -Version Latest

function Get-ExifJsonValue {
    param(
        [psobject]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function New-CaptureDateResult {
    param(
        [bool]$Success,
        [Nullable[datetime]]$DateTime,
        [string]$Source,
        [string]$Pattern,
        [string[]]$Warnings
    )

    [pscustomobject]@{
        Success = $Success
        DateTime = $DateTime
        Source = $Source
        Pattern = $Pattern
        Warnings = @($Warnings)
    }
}

function ConvertTo-NullableDateTime {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $text = $Value.Trim()
    if ($text -match '^\d{4}:\d{2}:\d{2}\s+\d{2}:\d{2}:\d{2}') {
        $text = $text -replace '^(\d{4}):(\d{2}):(\d{2})\s+', '$1-$2-$3T'
    }

    try {
        return [datetimeoffset]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture).DateTime
    } catch {
    }

    try {
        return [datetime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return $null
    }
}

function Test-IsDateOnlyString {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value.Trim() -match '^\d{4}[:\-]\d{2}[:\-]\d{2}$'
}

function Test-IsValidCaptureDate {
    param(
        [Nullable[datetime]]$Date,
        [string]$RawValue,
        [Nullable[datetime]]$FileNameDate
    )

    if ($null -eq $Date) {
        return $false
    }

    if ($Date -lt [datetime]'2000-01-01T00:00:00') {
        return $false
    }

    if ($Date -gt (Get-Date).AddDays(1)) {
        return $false
    }

    if ($Date.Date -eq [datetime]'1904-01-01' -or $Date.Date -eq [datetime]'1970-01-01') {
        return $false
    }

    if ((Test-IsDateOnlyString -Value $RawValue) -and $null -ne $FileNameDate) {
        return $false
    }

    return $true
}

function Get-VideoDateFromMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExifToolPath,

        [Nullable[datetime]]$FileNameDate
    )

    $args = @(
        '-j'
        '-QuickTime:MediaCreateDate'
        '-QuickTime:CreateDate'
        '-QuickTime:TrackCreateDate'
        '-QuickTime:ModifyDate'
        '-EXIF:DateTimeOriginal'
        '-EXIF:CreateDate'
        '-XMP:CreateDate'
        '-Keys:CreationDate'
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

    $parsed = $output | ConvertFrom-Json
    $item = if ($parsed -is [System.Array]) { $parsed[0] } else { $parsed }

    $candidates = @(
        @{ Name = 'QuickTime:MediaCreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'QuickTime:MediaCreateDate') }
        @{ Name = 'MediaCreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'MediaCreateDate') }
        @{ Name = 'QuickTime:CreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'QuickTime:CreateDate') }
        @{ Name = 'CreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'CreateDate') }
        @{ Name = 'QuickTime:TrackCreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'QuickTime:TrackCreateDate') }
        @{ Name = 'TrackCreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'TrackCreateDate') }
        @{ Name = 'QuickTime:ModifyDate'; Value = (Get-ExifJsonValue -Object $item -Name 'QuickTime:ModifyDate') }
        @{ Name = 'ModifyDate'; Value = (Get-ExifJsonValue -Object $item -Name 'ModifyDate') }
        @{ Name = 'EXIF:DateTimeOriginal'; Value = (Get-ExifJsonValue -Object $item -Name 'EXIF:DateTimeOriginal') }
        @{ Name = 'DateTimeOriginal'; Value = (Get-ExifJsonValue -Object $item -Name 'DateTimeOriginal') }
        @{ Name = 'EXIF:CreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'EXIF:CreateDate') }
        @{ Name = 'XMP:CreateDate'; Value = (Get-ExifJsonValue -Object $item -Name 'XMP:CreateDate') }
        @{ Name = 'Keys:CreationDate'; Value = (Get-ExifJsonValue -Object $item -Name 'Keys:CreationDate') }
    )

    foreach ($candidate in $candidates) {
        $rawValue = [string]$candidate.Value
        $parsedDate = ConvertTo-NullableDateTime -Value $rawValue
        if (Test-IsValidCaptureDate -Date $parsedDate -RawValue $rawValue -FileNameDate $FileNameDate) {
            return New-CaptureDateResult -Success $true -DateTime $parsedDate -Source 'Metadata' -Pattern $candidate.Name -Warnings @()
        }
    }

    return New-CaptureDateResult -Success $false -DateTime $null -Source 'None' -Pattern $null -Warnings @('No valid metadata date found.')
}

function Get-DateMatchResult {
    param(
        [string]$BaseName,
        [string]$PatternName,
        [string]$RegexPattern,
        [scriptblock]$Parser
    )

    $match = [regex]::Match($BaseName, $RegexPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    $date = & $Parser $match
    if ($null -eq $date) {
        return New-CaptureDateResult -Success $false -DateTime $null -Source 'None' -Pattern $PatternName -Warnings @("Filename matched pattern '$PatternName' but contains an invalid date.")
    }

    return New-CaptureDateResult -Success $true -DateTime $date -Source 'FileName' -Pattern $PatternName -Warnings @()
}

function New-DateTimeFromParts {
    param(
        [string]$Year,
        [string]$Month,
        [string]$Day,
        [string]$Hour,
        [string]$Minute,
        [string]$Second,
        [string]$Millisecond = '0'
    )

    $currentYear = (Get-Date).Year
    $yearValue = [int]$Year
    $monthValue = [int]$Month
    $dayValue = [int]$Day
    $hourValue = [int]$Hour
    $minuteValue = [int]$Minute
    $secondValue = [int]$Second
    $millisecondValue = [int]$Millisecond

    if ($yearValue -lt 2000 -or $yearValue -gt ($currentYear + 1)) {
        return $null
    }

    if ($monthValue -lt 1 -or $monthValue -gt 12) {
        return $null
    }

    if ($dayValue -lt 1 -or $dayValue -gt 31) {
        return $null
    }

    if ($hourValue -lt 0 -or $hourValue -gt 23) {
        return $null
    }

    if ($minuteValue -lt 0 -or $minuteValue -gt 59) {
        return $null
    }

    if ($secondValue -lt 0 -or $secondValue -gt 59) {
        return $null
    }

    if ($millisecondValue -lt 0 -or $millisecondValue -gt 999) {
        return $null
    }

    try {
        return [datetime]::new($yearValue, $monthValue, $dayValue, $hourValue, $minuteValue, $secondValue, $millisecondValue)
    } catch {
        return $null
    }
}

function Get-VideoDateFromFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$DefaultTimezoneOffset = '+00:00'
    )

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)

    $patterns = @(
        @{ Name = 'Imou_yyyyMMddHHmmssfff_prefix'; Regex = '^(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})(?<fff>\d{3})_'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value $m.Groups['fff'].Value } }
        @{ Name = 'Insta360_VID_yyyyMMdd_HHmmss_suffix'; Regex = '^VID_(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})_(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})(?:_.*)+$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'VID_yyyyMMdd_HHmmss'; Regex = '^VID_(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})_(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'AndroidPrefix'; Regex = '^(?:IMG|PXL)_(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})_(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})(?:\d{3})?$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'BasicCompact'; Regex = '^(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})[_-](?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'BasicIsoCompact'; Regex = '^(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})T(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})Z?$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'DashedSpaced'; Regex = '^(?<y>\d{4})[-_.](?<m>\d{2})[-_.](?<d>\d{2})[ _](?<hh>\d{2})[.\-_:](?<mm>\d{2})[.\-_:](?<ss>\d{2})$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'IsoOffset'; Regex = '^(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})T(?<hh>\d{2})[-:](?<mm>\d{2})[-:](?<ss>\d{2})(?<tz>Z|[+\-]\d{2}:?\d{2})$'; Parser = {
                param($m)
                $offset = $m.Groups['tz'].Value
                $offsetText = if ($offset -eq 'Z') { '+00:00' } elseif ($offset -match '^[+\-]\d{4}$') { $offset.Insert(3, ':') } else { $offset }
                try {
                    return [datetimeoffset]::ParseExact(
                        ('{0}-{1}-{2}T{3}:{4}:{5}{6}' -f $m.Groups['y'].Value, $m.Groups['m'].Value, $m.Groups['d'].Value, $m.Groups['hh'].Value, $m.Groups['mm'].Value, $m.Groups['ss'].Value, $offsetText),
                        'yyyy-MM-ddTHH:mm:ssK',
                        [System.Globalization.CultureInfo]::InvariantCulture
                    ).LocalDateTime
                } catch {
                    return $null
                }
            }
        }
        @{ Name = 'WhatsAppTelegram'; Regex = '^(?:WhatsApp Video|Telegram Video) (?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2}) at (?<hh>\d{2})\.(?<mm>\d{2})\.(?<ss>\d{2})$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'Signal'; Regex = '^Signal-(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})-(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'DJI'; Regex = '^DJI_(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})(?:_|$)'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
        @{ Name = 'GoPro'; Regex = '^(?:GOPR\d{4}|GX\d{6})_(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})_(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})$'; Parser = { param($m) New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value } }
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($pattern in $patterns) {
        $result = Get-DateMatchResult -BaseName $baseName -PatternName $pattern.Name -RegexPattern $pattern.Regex -Parser $pattern.Parser
        if ($null -ne $result) {
            if ($result.Success) {
                return $result
            }

            foreach ($warning in @($result.Warnings)) {
                $warnings.Add($warning)
            }
        }
    }

    $generic17Digit = Get-DateMatchResult -BaseName $baseName -PatternName 'Generic_yyyyMMddHHmmssfff' -RegexPattern '(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})(?<hh>\d{2})(?<mm>\d{2})(?<ss>\d{2})(?<fff>\d{3})' -Parser {
        param($m)
        New-DateTimeFromParts $m.Groups['y'].Value $m.Groups['m'].Value $m.Groups['d'].Value $m.Groups['hh'].Value $m.Groups['mm'].Value $m.Groups['ss'].Value $m.Groups['fff'].Value
    }

    if ($null -ne $generic17Digit) {
        if ($generic17Digit.Success) {
            return $generic17Digit
        }

        foreach ($warning in @($generic17Digit.Warnings)) {
            $warnings.Add($warning)
        }
    }

    if ($warnings.Count -eq 0) {
        $warnings.Add('Filename does not match any supported date pattern.')
    }

    return New-CaptureDateResult -Success $false -DateTime $null -Source 'None' -Pattern $null -Warnings @($warnings)
}

function Resolve-VideoCaptureDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExifToolPath,

        [Parameter(Mandatory)]
        [psobject]$DateConfig
    )

    $fileNameResult = Get-VideoDateFromFileName -Path $Path -DefaultTimezoneOffset ([string]$DateConfig.defaultTimezoneOffset)
    $metadataResult = Get-VideoDateFromMetadata -Path $Path -ExifToolPath $ExifToolPath -FileNameDate $fileNameResult.DateTime

    if ($metadataResult.Success) {
        return $metadataResult
    }

    if ($fileNameResult.Success) {
        return $fileNameResult
    }

    $warnings = @()
    $warnings += @($metadataResult.Warnings)
    $warnings += @($fileNameResult.Warnings)
    $warnings += 'Capture date could not be determined.'
    $warnings += 'Capture date was left empty.'
    return New-CaptureDateResult -Success $false -DateTime $null -Source 'None' -Pattern $null -Warnings $warnings
}

function Set-VideoCaptureDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [datetime]$CaptureDate,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$ExifToolPath,

        [switch]$SetAllCommonDateTags
    )

    if ($Source -eq 'None') {
        return $null
    }

    if ($Source -eq 'Metadata' -and -not $SetAllCommonDateTags) {
        return $null
    }

    $dateText = $CaptureDate.ToString('yyyy:MM:dd HH:mm:ss')
    $args = @(
        '-overwrite_original'
        "-QuickTime:CreateDate=$dateText"
        "-QuickTime:ModifyDate=$dateText"
        "-QuickTime:TrackCreateDate=$dateText"
        "-QuickTime:TrackModifyDate=$dateText"
        "-QuickTime:MediaCreateDate=$dateText"
        "-QuickTime:MediaModifyDate=$dateText"
        "-Keys:CreationDate=$dateText"
        "-XMP:CreateDate=$dateText"
        "-XMP:ModifyDate=$dateText"
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
        throw "ExifTool capture date write failed for '$Path': $output"
    }

    return $output.Trim()
}

Export-ModuleMember -Function Get-VideoDateFromMetadata, Get-VideoDateFromFileName, Resolve-VideoCaptureDate, Set-VideoCaptureDate
