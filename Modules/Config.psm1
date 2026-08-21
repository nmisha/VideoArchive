Set-StrictMode -Version Latest

function Resolve-VideoArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    return [System.IO.Path]::GetFullPath((Join-Path -Path $ProjectRoot -ChildPath $RelativePath))
}

function Resolve-OptionalVideoArchivePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $null
    }

    return Resolve-VideoArchivePath -ProjectRoot $ProjectRoot -RelativePath $RelativePath
}

function Get-OptionalJsonPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Object,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-HasNvidiaRtxAdapter {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]]$Adapters
    )

    foreach ($adapter in @($Adapters)) {
        $name = [string]$adapter.Name
        $vendor = [string]$adapter.AdapterCompatibility
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $isNvidia = $vendor -match 'NVIDIA' -or $name -match 'NVIDIA'
        $isRtx = $name -match '(^|\s)RTX(\s|$)|GeForce\s+RTX|Quadro\s+RTX|RTX\s+A\d|RTX\s+\d{3,4}'
        if ($isNvidia -and $isRtx) {
            return $true
        }
    }

    return $false
}

function Get-VideoArchiveHardwareProfile {
    [CmdletBinding()]
    param(
        [object[]]$Adapters
    )

    $resolvedAdapters = @()
    if ($PSBoundParameters.ContainsKey('Adapters') -and $null -ne $Adapters) {
        $resolvedAdapters = @($Adapters)
    }

    if ((@($resolvedAdapters)).Count -eq 0) {
        try {
            $resolvedAdapters = @(
                Get-CimInstance Win32_VideoController -ErrorAction Stop |
                    Select-Object Name, AdapterCompatibility, Status
            )
        } catch {
            $resolvedAdapters = @()
        }
    }

    [pscustomobject]@{
        Adapters = @($resolvedAdapters)
        HasNvidiaRtx = (Test-HasNvidiaRtxAdapter -Adapters @($resolvedAdapters))
    }
}

function Read-VideoArchiveJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Import-VideoArchiveConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot,

        [string]$PresetName
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $config = Read-VideoArchiveJson -Path (Join-Path $resolvedRoot 'config.json')
    $presets = Read-VideoArchiveJson -Path (Join-Path $resolvedRoot 'presets.json')
    $smartSkip = Read-VideoArchiveJson -Path (Join-Path $resolvedRoot 'smartskip.json')
    $devices = Read-VideoArchiveJson -Path (Join-Path $resolvedRoot 'devices.json')

    if ($null -eq $smartSkip.PSObject.Properties['encodeSmallModernFiles']) {
        Add-Member -InputObject $smartSkip -NotePropertyName encodeSmallModernFiles -NotePropertyValue $false
    }
    if ($null -eq $smartSkip.PSObject.Properties['legacySourceExtensions']) {
        Add-Member -InputObject $smartSkip -NotePropertyName legacySourceExtensions -NotePropertyValue @('.mts', '.m2ts', '.avi', '.wmv', '.webm')
    }
    $normalizedLegacyExtensions = @(
        foreach ($extension in @($smartSkip.legacySourceExtensions)) {
            $normalizedExtension = ([string]$extension).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($normalizedExtension)) { continue }
            if (-not $normalizedExtension.StartsWith('.')) { $normalizedExtension = ".${normalizedExtension}" }
            $normalizedExtension
        }
    ) | Select-Object -Unique
    $smartSkip.legacySourceExtensions = @($normalizedLegacyExtensions)

    if ([string]::IsNullOrWhiteSpace($PresetName)) {
        $PresetName = $config.defaultPreset
    }

    $preset = $presets.PSObject.Properties[$PresetName]
    if ($null -eq $preset) {
        $availablePresets = $presets.PSObject.Properties.Name -join ', '
        throw "Preset '$PresetName' not found. Available presets: $availablePresets"
    }

    $outputContainer = Get-OptionalJsonPropertyValue -Object $config.output -Name 'container'
    if ([string]::IsNullOrWhiteSpace([string]$outputContainer)) {
        $outputContainer = 'mp4'
    }
    $outputContainer = ([string]$outputContainer).ToLowerInvariant()
    if ($outputContainer -notin @('mp4', 'mkv', 'source')) {
        throw "Unsupported output container '$outputContainer'. Expected 'mp4', 'mkv', or 'source'."
    }

    $audioConfig = Get-OptionalJsonPropertyValue -Object $config -Name 'audio'
    if ($null -eq $audioConfig) {
        $audioConfig = [pscustomobject]@{ mode = 'copy'; aacBitrateKbps = 256 }
    }
    if ($null -eq $audioConfig.PSObject.Properties['mode']) { Add-Member -InputObject $audioConfig -NotePropertyName mode -NotePropertyValue 'copy' }
    if ($null -eq $audioConfig.PSObject.Properties['aacBitrateKbps']) { Add-Member -InputObject $audioConfig -NotePropertyName aacBitrateKbps -NotePropertyValue 256 }
    $audioConfig.mode = ([string]$audioConfig.mode).ToLowerInvariant()
    if ($audioConfig.mode -notin @('copy', 'aac')) {
        throw "Unsupported audio mode '$($audioConfig.mode)'. Expected 'copy' or 'aac'."
    }
    $aacBitrateValue = [string]$audioConfig.aacBitrateKbps
    if ($aacBitrateValue -ieq 'source') {
        $audioConfig.aacBitrateKbps = 'source'
    } else {
        $parsedAacBitrate = 0
        if (-not [int]::TryParse($aacBitrateValue, [ref]$parsedAacBitrate) -or $parsedAacBitrate -le 0) {
            throw "audio.aacBitrateKbps must be a positive integer or 'source'."
        }
        $audioConfig.aacBitrateKbps = $parsedAacBitrate
    }

    $dateConfig = $config.dates
    if ($null -eq $dateConfig) {
        $dateConfig = [pscustomobject]@{}
    }
    if ($null -eq $dateConfig.PSObject.Properties['timezoneMode']) { Add-Member -InputObject $dateConfig -NotePropertyName timezoneMode -NotePropertyValue 'sourceOrZone' }
    if ($null -eq $dateConfig.PSObject.Properties['defaultTimezone']) { Add-Member -InputObject $dateConfig -NotePropertyName defaultTimezone -NotePropertyValue 'Europe/Moscow' }
    if ($null -eq $dateConfig.PSObject.Properties['unknownTimezonePolicy']) { Add-Member -InputObject $dateConfig -NotePropertyName unknownTimezonePolicy -NotePropertyValue 'keepLocal' }
    if ($null -eq $dateConfig.PSObject.Properties['fileDateFallbackMode']) { Add-Member -InputObject $dateConfig -NotePropertyName fileDateFallbackMode -NotePropertyValue 'disabled' }
    if ($null -eq $dateConfig.PSObject.Properties['preferFileNameOverFileSystemDates']) { Add-Member -InputObject $dateConfig -NotePropertyName preferFileNameOverFileSystemDates -NotePropertyValue $true }
    if ($null -eq $dateConfig.PSObject.Properties['setAllCommonDateTags']) { Add-Member -InputObject $dateConfig -NotePropertyName setAllCommonDateTags -NotePropertyValue $true }
    if ($null -eq $dateConfig.PSObject.Properties['strictDateMode']) { Add-Member -InputObject $dateConfig -NotePropertyName strictDateMode -NotePropertyValue $false }
    $dateConfig.timezoneMode = ([string]$dateConfig.timezoneMode).ToLowerInvariant()
    if ($dateConfig.timezoneMode -notin @('sourceorzone', 'sourceonly', 'none')) {
        throw "Unsupported dates.timezoneMode '$($dateConfig.timezoneMode)'. Expected 'sourceOrZone', 'sourceOnly', or 'none'."
    }
    $dateConfig.timezoneMode = switch ($dateConfig.timezoneMode) { 'sourceorzone' { 'sourceOrZone' }; 'sourceonly' { 'sourceOnly' }; default { 'none' } }
    if ([string]$dateConfig.unknownTimezonePolicy -ne 'keepLocal') {
        throw "Unsupported dates.unknownTimezonePolicy '$($dateConfig.unknownTimezonePolicy)'. Expected 'keepLocal'."
    }

    if ($dateConfig.timezoneMode -eq 'sourceOrZone') {
        $configuredTimeZone = [string]$dateConfig.defaultTimezone
        $timeZoneFound = $false
        $candidateTimeZones = @($configuredTimeZone)
        if ($configuredTimeZone -eq 'Europe/Moscow') { $candidateTimeZones += 'Russian Standard Time' }
        if ($configuredTimeZone -eq 'Russian Standard Time') { $candidateTimeZones += 'Europe/Moscow' }
        foreach ($candidateTimeZone in $candidateTimeZones) {
            try { $null = [TimeZoneInfo]::FindSystemTimeZoneById($candidateTimeZone); $timeZoneFound = $true; break } catch { }
        }
        if (-not $timeZoneFound) {
            throw "dates.defaultTimezone '$configuredTimeZone' is not available on this system."
        }
    }

    $advancedConfig = Get-OptionalJsonPropertyValue -Object $config -Name 'advanced'
    if ($null -eq $advancedConfig) {
        $advancedConfig = [pscustomobject]@{ rotationMode = 'none'; rotationDegrees = 0 }
    }
    if ($null -eq $advancedConfig.PSObject.Properties['rotationMode']) { Add-Member -InputObject $advancedConfig -NotePropertyName rotationMode -NotePropertyValue 'none' }
    if ($null -eq $advancedConfig.PSObject.Properties['rotationDegrees']) { Add-Member -InputObject $advancedConfig -NotePropertyName rotationDegrees -NotePropertyValue 0 }
    $advancedConfig.rotationMode = ([string]$advancedConfig.rotationMode).ToLowerInvariant()
    if ($advancedConfig.rotationMode -notin @('none', 'metadata', 'physical')) {
        throw "Unsupported advanced.rotationMode '$($advancedConfig.rotationMode)'. Expected 'none', 'metadata', or 'physical'."
    }
    $rotationDegrees = 0
    if (-not [int]::TryParse([string]$advancedConfig.rotationDegrees, [ref]$rotationDegrees) -or $rotationDegrees -notin @(0, 90, 180, 270)) {
        throw 'advanced.rotationDegrees must be 0, 90, 180, or 270.'
    }
    $advancedConfig.rotationDegrees = $rotationDegrees
    if ($advancedConfig.rotationMode -ne 'none' -and $rotationDegrees -eq 0) {
        $advancedConfig.rotationMode = 'none'
    }

    [pscustomobject]@{
        ProjectRoot = $resolvedRoot
        AppName = $config.appName
        DefaultPreset = $config.defaultPreset
        PresetName = $PresetName
        Preset = $preset.Value
        Presets = $presets
        SmartSkip = $smartSkip
        Devices = $devices
        Extensions = @($config.extensions | ForEach-Object { $_.ToLowerInvariant() })
        Output = [pscustomobject]@{
            HdrSuffix = $config.output.hdrSuffix
            SdrSuffix = $config.output.sdrSuffix
            Container = $outputContainer
            LogsFolder = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.output.logsFolder
            TempFolder = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.output.tempFolder
        }
        Metadata = if ($null -ne $config.metadata) {
            if ($null -eq $config.metadata.PSObject.Properties['fileTimestampMode']) {
                Add-Member -InputObject $config.metadata -NotePropertyName fileTimestampMode -NotePropertyValue 'captureDate'
            }
            $config.metadata
        } else {
            [pscustomobject]@{
                copyAllMetadata = $true
                preserveWindowsTimestamps = $true
                fileTimestampMode = 'captureDate'
            }
        }
        Audio = $audioConfig
        Dates = $dateConfig
        Advanced = $advancedConfig
        Encoder = if ($null -ne $config.encoder) {
            if ($null -eq $config.encoder.PSObject.Properties['defaultBackend']) {
                Add-Member -InputObject $config.encoder -NotePropertyName defaultBackend -NotePropertyValue 'auto'
            }
            if ($null -eq $config.encoder.PSObject.Properties['defaultCodec']) {
                Add-Member -InputObject $config.encoder -NotePropertyName defaultCodec -NotePropertyValue 'hevc'
            }
            if ($null -eq $config.encoder.PSObject.Properties['allowHdrAv1']) {
                Add-Member -InputObject $config.encoder -NotePropertyName allowHdrAv1 -NotePropertyValue $false
            }
            if ($null -eq $config.encoder.PSObject.Properties['detectHardwareOnStartup']) {
                Add-Member -InputObject $config.encoder -NotePropertyName detectHardwareOnStartup -NotePropertyValue $true
            }
            if ($null -eq $config.encoder.PSObject.Properties['alwaysPromptEncoderChoiceWithoutRtx']) {
                Add-Member -InputObject $config.encoder -NotePropertyName alwaysPromptEncoderChoiceWithoutRtx -NotePropertyValue $true
            }
            if ($null -eq $config.encoder.PSObject.Properties['alwaysPromptEncoderChoice']) {
                Add-Member -InputObject $config.encoder -NotePropertyName alwaysPromptEncoderChoice -NotePropertyValue $false
            }
            if ($null -eq $config.encoder.PSObject.Properties['autoBackendOrder']) {
                Add-Member -InputObject $config.encoder -NotePropertyName autoBackendOrder -NotePropertyValue @('nvenc', 'qsv', 'amf', 'software')
            }
            if ($null -eq $config.encoder.PSObject.Properties['preferredGpu']) {
                Add-Member -InputObject $config.encoder -NotePropertyName preferredGpu -NotePropertyValue 0
            }
            $config.encoder
        } else {
            [pscustomobject]@{
                defaultBackend = 'auto'
                defaultCodec = 'hevc'
                allowHdrAv1 = $false
                detectHardwareOnStartup = $true
                alwaysPromptEncoderChoiceWithoutRtx = $true
                alwaysPromptEncoderChoice = $false
                autoBackendOrder = @('nvenc', 'qsv', 'amf', 'software')
                preferredGpu = 0
            }
        }
        Tools = [pscustomobject]@{
            NvEnc = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.nvenc
            QsvEnc = Resolve-OptionalVideoArchivePath -ProjectRoot $resolvedRoot -RelativePath (Get-OptionalJsonPropertyValue -Object $config.tools -Name 'qsvenc')
            AmfEnc = Resolve-OptionalVideoArchivePath -ProjectRoot $resolvedRoot -RelativePath (Get-OptionalJsonPropertyValue -Object $config.tools -Name 'amfenc')
            Ffmpeg = Resolve-OptionalVideoArchivePath -ProjectRoot $resolvedRoot -RelativePath (Get-OptionalJsonPropertyValue -Object $config.tools -Name 'ffmpeg')
            ExifTool = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.exiftool
            MediaInfo = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.mediainfo
        }
    }
}

function Get-VideoArchivePresetCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $config = Read-VideoArchiveJson -Path (Join-Path $resolvedRoot 'config.json')
    $presets = Read-VideoArchiveJson -Path (Join-Path $resolvedRoot 'presets.json')

    $items = foreach ($property in $presets.PSObject.Properties) {
        [pscustomobject]@{
            Name = $property.Name
            Description = [string]$property.Value.description
            IsDefault = ($property.Name -eq [string]$config.defaultPreset)
        }
    }

    [pscustomobject]@{
        DefaultPreset = [string]$config.defaultPreset
        Presets = @($items)
    }
}

function Test-VideoArchiveTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config
    )

    $requiredTools = @{
        ExifTool = $Config.Tools.ExifTool
        MediaInfo = $Config.Tools.MediaInfo
    }

    $missing = @()
    foreach ($tool in $requiredTools.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $tool.Value -PathType Leaf)) {
            $missing += "{0}: {1}" -f $tool.Key, $tool.Value
        }
    }

    if ($missing.Count -gt 0) {
        throw "Required tools are missing:`n$($missing -join [Environment]::NewLine)"
    }

    $encoderTools = @(
        @{ Name = 'NVEncC'; Path = $Config.Tools.NvEnc }
        @{ Name = 'QSVEncC'; Path = $Config.Tools.QsvEnc }
        @{ Name = 'VCEEncC'; Path = $Config.Tools.AmfEnc }
        @{ Name = 'FFmpeg'; Path = $Config.Tools.Ffmpeg }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Path) -and (Test-Path -LiteralPath $_.Path -PathType Leaf) }

    if ($encoderTools.Count -eq 0) {
        throw 'No supported encoder tool was found. Expected one of NVEncC, QSVEncC, VCEEncC, or FFmpeg.'
    }

    return $true
}

Export-ModuleMember -Function Import-VideoArchiveConfig, Get-VideoArchivePresetCatalog, Test-VideoArchiveTools, Get-VideoArchiveHardwareProfile, Test-HasNvidiaRtxAdapter
