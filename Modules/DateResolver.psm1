Set-StrictMode -Version Latest

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'Utils.psm1') -Force

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
        [string[]]$Warnings,
        [Nullable[datetimeoffset]]$DateTimeOffset,
        [bool]$HasTimezone = $false,
        [string]$TimezoneSource = 'Unknown',
        [string]$TimezoneId
    )

    [pscustomobject]@{
        Success = $Success
        DateTime = $DateTime
        Source = $Source
        Pattern = $Pattern
        Warnings = @($Warnings)
        DateTimeOffset = $DateTimeOffset
        HasTimezone = $HasTimezone
        Offset = if ($HasTimezone -and $null -ne $DateTimeOffset) { $DateTimeOffset.ToString('zzz') } else { $null }
        TimezoneSource = $TimezoneSource
        TimezoneId = $TimezoneId
    }
}

function ConvertTo-CaptureDateValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject]@{ DateTime = $null; DateTimeOffset = $null; HasTimezone = $false }
    }

    $text = $Value.Trim()
    if ($text -match '^\d{4}:\d{2}:\d{2}\s+\d{2}:\d{2}:\d{2}') {
        $text = $text -replace '^(\d{4}):(\d{2}):(\d{2})\s+', '$1-$2-$3T'
    }

    $hasExplicitTimezone = $text -match '(?:Z|[+\-]\d{2}:?\d{2})$'
    if ($hasExplicitTimezone) {
        try {
            $dateWithOffset = [datetimeoffset]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
            return [pscustomobject]@{ DateTime = $dateWithOffset.DateTime; DateTimeOffset = $dateWithOffset; HasTimezone = $true }
        } catch {
        }
    }

    try {
        $localDate = [datetime]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)
        return [pscustomobject]@{ DateTime = [datetime]::SpecifyKind($localDate, [DateTimeKind]::Unspecified); DateTimeOffset = $null; HasTimezone = $false }
    } catch {
        return [pscustomobject]@{ DateTime = $null; DateTimeOffset = $null; HasTimezone = $false }
    }
}

function Get-CaptureDateTimeZone {
    param([psobject]$DateConfig)

    if ($null -eq $DateConfig -or $null -eq $DateConfig.PSObject.Properties['defaultTimezone']) {
        return $null
    }

    $configuredId = [string]$DateConfig.defaultTimezone
    if ([string]::IsNullOrWhiteSpace($configuredId)) {
        return $null
    }

    $candidateIds = @($configuredId)
    if ($configuredId -eq 'Europe/Moscow') { $candidateIds += 'Russian Standard Time' }
    if ($configuredId -eq 'Russian Standard Time') { $candidateIds += 'Europe/Moscow' }
    foreach ($candidateId in $candidateIds) {
        try { return [TimeZoneInfo]::FindSystemTimeZoneById($candidateId) } catch { }
    }

    return $null
}

function Add-CaptureDateTimezone {
    param(
        [Parameter(Mandatory)][psobject]$Result,
        [psobject]$DateConfig
    )

    if (-not $Result.Success -or $Result.HasTimezone) {
        return $Result
    }

    $mode = if ($null -ne $DateConfig -and $null -ne $DateConfig.PSObject.Properties['timezoneMode']) { [string]$DateConfig.timezoneMode } else { 'sourceOnly' }
    if ($mode -ne 'sourceOrZone') {
        $Result.Warnings = @($Result.Warnings) + 'Capture date has no UTC offset; local wall-clock time was preserved without UTC conversion.'
        return $Result
    }

    $timeZone = Get-CaptureDateTimeZone -DateConfig $DateConfig
    if ($null -eq $timeZone) {
        $Result.Warnings = @($Result.Warnings) + 'Capture date has no UTC offset and the configured time zone is unavailable; local wall-clock time was preserved.'
        return $Result
    }

    $wallDate = [datetime]::SpecifyKind($Result.DateTime, [DateTimeKind]::Unspecified)
    if ($timeZone.IsInvalidTime($wallDate)) {
        $Result.Warnings = @($Result.Warnings) + "Capture date falls into an invalid local-time interval for '$($timeZone.Id)'; local wall-clock time was preserved."
        return $Result
    }
    if ($timeZone.IsAmbiguousTime($wallDate)) {
        $Result.Warnings = @($Result.Warnings) + "Capture date is ambiguous in '$($timeZone.Id)'; local wall-clock time was preserved without choosing an offset."
        return $Result
    }

    $offset = $timeZone.GetUtcOffset($wallDate)
    $dateWithOffset = [datetimeoffset]::new($wallDate, $offset)
    $Result.DateTimeOffset = $dateWithOffset
    $Result.HasTimezone = $true
    $Result.Offset = $dateWithOffset.ToString('zzz')
    $Result.TimezoneSource = 'ConfiguredZone'
    $Result.TimezoneId = $timeZone.Id
    return $Result
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

function Get-VideoDateFromFileSystem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateSet('disabled', 'creationTime', 'lastWriteTime')]
        [string]$FallbackMode = 'disabled'
    )

    if ($FallbackMode -eq 'disabled') {
        return New-CaptureDateResult -Success $false -DateTime $null -Source 'None' -Pattern $null -Warnings @('Filesystem date fallback is disabled.')
    }

    $file = Get-Item -LiteralPath $Path
    $candidateDate = switch ($FallbackMode) {
        'creationTime' { $file.CreationTime }
        'lastWriteTime' { $file.LastWriteTime }
        default { $null }
    }

    $pattern = switch ($FallbackMode) {
        'creationTime' { 'FileSystemCreationTime' }
        'lastWriteTime' { 'FileSystemLastWriteTime' }
        default { $null }
    }

    if (Test-IsValidCaptureDate -Date $candidateDate -RawValue $candidateDate.ToString('s') -FileNameDate $null) {
        return New-CaptureDateResult -Success $true -DateTime $candidateDate -Source 'FileSystem' -Pattern $pattern -Warnings @()
    }

    return New-CaptureDateResult -Success $false -DateTime $null -Source 'None' -Pattern $pattern -Warnings @("No valid filesystem date found for fallback mode '$FallbackMode'.")
}

function Get-VideoDateFromMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExifToolPath,

        [Nullable[datetime]]$FileNameDate,

        [psobject]$DateConfig
    )

    $args = @(
        '-j'
        '-QuickTime:MediaCreateDate'
        '-QuickTime:CreateDate'
        '-QuickTime:TrackCreateDate'
        '-QuickTime:ModifyDate'
        '-DateTimeOriginal'
        '-CreateDate'
        '-EXIF:DateTimeOriginal'
        '-EXIF:CreateDate'
        '-XMP:CreateDate'
        '-Keys:CreationDate'
        $Path
    )

    $output = Invoke-VideoArchiveJsonTool `
        -ExecutablePath $ExifToolPath `
        -Arguments $args `
        -Operation "ExifTool metadata read for '$Path'"

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

    $orderedCandidates = @($candidates | Where-Object { [string]$_.Value -match '(?:Z|[+\-]\d{2}:?\d{2})$' })
    $orderedCandidates += @($candidates | Where-Object { [string]$_.Value -notmatch '(?:Z|[+\-]\d{2}:?\d{2})$' })
    foreach ($candidate in $orderedCandidates) {
        $rawValue = [string]$candidate.Value
        $parsedDate = ConvertTo-CaptureDateValue -Value $rawValue
        if (Test-IsValidCaptureDate -Date $parsedDate.DateTime -RawValue $rawValue -FileNameDate $FileNameDate) {
            $result = New-CaptureDateResult -Success $true -DateTime $parsedDate.DateTime -Source 'Metadata' -Pattern $candidate.Name -Warnings @() -DateTimeOffset $parsedDate.DateTimeOffset -HasTimezone:$parsedDate.HasTimezone -TimezoneSource $(if ($parsedDate.HasTimezone) { 'SourceMetadata' } else { 'Unknown' })
            return Add-CaptureDateTimezone -Result $result -DateConfig $DateConfig
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

    if ($date -is [datetimeoffset]) {
        return New-CaptureDateResult -Success $true -DateTime $date.DateTime -Source 'FileName' -Pattern $PatternName -Warnings @() -DateTimeOffset $date -HasTimezone:$true -TimezoneSource 'FileName'
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
                    )
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

    $legacyOffset = if ($null -ne $DateConfig.PSObject.Properties['defaultTimezoneOffset']) { [string]$DateConfig.defaultTimezoneOffset } else { '+00:00' }
    $fileNameResult = Get-VideoDateFromFileName -Path $Path -DefaultTimezoneOffset $legacyOffset
    $fileNameResult = Add-CaptureDateTimezone -Result $fileNameResult -DateConfig $DateConfig
    $metadataResult = Get-VideoDateFromMetadata -Path $Path -ExifToolPath $ExifToolPath -FileNameDate $fileNameResult.DateTime -DateConfig $DateConfig

    if ($metadataResult.Success) {
        return $metadataResult
    }

    if ($fileNameResult.Success) {
        return $fileNameResult
    }

    $fileSystemResult = Get-VideoDateFromFileSystem -Path $Path -FallbackMode ([string]$DateConfig.fileDateFallbackMode)
    if ($fileSystemResult.Success) {
        return Add-CaptureDateTimezone -Result $fileSystemResult -DateConfig $DateConfig
    }

    $warnings = @()
    $warnings += @($metadataResult.Warnings)
    $warnings += @($fileNameResult.Warnings)
    $warnings += @($fileSystemResult.Warnings)
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

        [Nullable[datetimeoffset]]$CaptureDateTimeOffset,

        [switch]$HasTimezone,

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

    $localDateText = $CaptureDate.ToString('yyyy:MM:dd HH:mm:ss')
    $args = @('-overwrite_original')
    if ($HasTimezone -and $null -ne $CaptureDateTimeOffset) {
        $utcDateText = $CaptureDateTimeOffset.UtcDateTime.ToString('yyyy:MM:dd HH:mm:ss')
        $offsetDateText = $CaptureDateTimeOffset.ToString('yyyy:MM:dd HH:mm:sszzz')
        $args += @(
            "-QuickTime:CreateDate=$utcDateText"
            "-QuickTime:ModifyDate=$utcDateText"
            "-QuickTime:TrackCreateDate=$utcDateText"
            "-QuickTime:TrackModifyDate=$utcDateText"
            "-QuickTime:MediaCreateDate=$utcDateText"
            "-QuickTime:MediaModifyDate=$utcDateText"
            "-Keys:CreationDate=$offsetDateText"
            "-XMP:CreateDate=$offsetDateText"
            "-XMP:ModifyDate=$offsetDateText"
        )
    } else {
        $args += @(
            '-QuickTime:CreateDate='
            '-QuickTime:ModifyDate='
            '-QuickTime:TrackCreateDate='
            '-QuickTime:TrackModifyDate='
            '-QuickTime:MediaCreateDate='
            '-QuickTime:MediaModifyDate='
            "-Keys:CreationDate=$localDateText"
            "-XMP:CreateDate=$localDateText"
            "-XMP:ModifyDate=$localDateText"
        )
    }
    $args += $Path

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
