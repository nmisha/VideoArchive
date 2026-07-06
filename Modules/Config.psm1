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
        Metadata = $config.metadata
        Tools = [pscustomobject]@{
            NvEnc = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.nvenc
            ExifTool = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.exiftool
            MediaInfo = Resolve-VideoArchivePath -ProjectRoot $resolvedRoot -RelativePath $config.tools.mediainfo
        }
    }
}

function Test-VideoArchiveTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config
    )

    $requiredTools = @{
        NVEncC = $Config.Tools.NvEnc
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

    return $true
}

Export-ModuleMember -Function Import-VideoArchiveConfig, Test-VideoArchiveTools
