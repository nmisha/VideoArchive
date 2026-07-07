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

    if ([string]::IsNullOrWhiteSpace($PresetName)) {
        $PresetName = $config.defaultPreset
    }

    $preset = $presets.PSObject.Properties[$PresetName]
    if ($null -eq $preset) {
        $availablePresets = $presets.PSObject.Properties.Name -join ', '
        throw "Preset '$PresetName' not found. Available presets: $availablePresets"
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
        Dates = if ($null -ne $config.dates) {
            if ($null -eq $config.dates.PSObject.Properties['fileDateFallbackMode']) {
                Add-Member -InputObject $config.dates -NotePropertyName fileDateFallbackMode -NotePropertyValue 'disabled'
            }
            $config.dates
        } else {
            [pscustomobject]@{
                timezoneMode = 'none'
                defaultTimezoneOffset = '+03:00'
                preferFileNameOverFileSystemDates = $true
                fileDateFallbackMode = 'disabled'
                setAllCommonDateTags = $true
                strictDateMode = $false
            }
        }
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
                autoBackendOrder = @('nvenc', 'qsv', 'amf', 'software')
                preferredGpu = 0
            }
        }
        Tools = [pscustomobject]@{
            NvEnc = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.nvenc
            QsvEnc = Resolve-OptionalVideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.qsvenc
            AmfEnc = Resolve-OptionalVideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.amfenc
            Ffmpeg = Resolve-OptionalVideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.ffmpeg
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

Export-ModuleMember -Function Import-VideoArchiveConfig, Get-VideoArchivePresetCatalog, Test-VideoArchiveTools
