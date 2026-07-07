Import-Module "$PSScriptRoot\..\..\Modules\Config.psm1" -Force

Describe 'Config hardware detection' {
    It 'detects NVIDIA RTX adapters' {
        $adapters = @(
            [pscustomobject]@{ Name = 'Intel(R) UHD Graphics 770'; AdapterCompatibility = 'Intel Corporation' },
            [pscustomobject]@{ Name = 'NVIDIA GeForce RTX 3080 Ti'; AdapterCompatibility = 'NVIDIA' }
        )

        $result = Test-HasNvidiaRtxAdapter -Adapters $adapters

        $result | Should Be $true
    }

    It 'does not treat non-RTX NVIDIA adapters as RTX' {
        $adapters = @(
            [pscustomobject]@{ Name = 'NVIDIA GeForce GTX 1660'; AdapterCompatibility = 'NVIDIA' }
        )

        $result = Test-HasNvidiaRtxAdapter -Adapters $adapters

        $result | Should Be $false
    }

    It 'returns a hardware profile from supplied adapters' {
        $adapters = @(
            [pscustomobject]@{ Name = 'NVIDIA RTX A2000'; AdapterCompatibility = 'NVIDIA'; Status = 'OK' }
        )

        $profile = Get-VideoArchiveHardwareProfile -Adapters $adapters

        $profile.HasNvidiaRtx | Should Be $true
        $profile.Adapters.Count | Should Be 1
    }

    It 'returns an empty non-RTX profile when adapters are omitted' {
        Mock Get-CimInstance { @() } -ModuleName Config

        $profile = Get-VideoArchiveHardwareProfile

        $profile.HasNvidiaRtx | Should Be $false
        $profile.Adapters.Count | Should Be 0
    }

    It 'adds encoder prompt defaults when missing from config' {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveConfig_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        try {
            @'
{
  "appName": "VideoArchive",
  "defaultPreset": "Balanced",
  "extensions": [".mp4"],
  "output": {
    "hdrSuffix": "_HDR_Encoded",
    "sdrSuffix": "_SDR_Encoded",
    "logsFolder": "Logs",
    "tempFolder": "Temp"
  },
  "metadata": {
    "copyAllMetadata": true,
    "preserveWindowsTimestamps": true,
    "fileTimestampMode": "captureDate"
  },
  "dates": {
    "timezoneMode": "none",
    "defaultTimezoneOffset": "+03:00",
    "preferFileNameOverFileSystemDates": true,
    "fileDateFallbackMode": "disabled",
    "setAllCommonDateTags": true,
    "strictDateMode": false
  },
  "encoder": {
    "defaultBackend": "auto",
    "defaultCodec": "hevc",
    "allowHdrAv1": false,
    "autoBackendOrder": ["nvenc", "qsv", "amf", "software"],
    "preferredGpu": 0
  },
  "tools": {
    "nvenc": "NVEncC/NVEncC64.exe",
    "exiftool": "ExifTool/exiftool.exe",
    "mediainfo": "MediaInfo/MediaInfo.exe"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'config.json') -Encoding utf8

            @'
{
  "Balanced": {
    "description": "Recommended balance"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'presets.json') -Encoding utf8

            '{}' | Set-Content -LiteralPath (Join-Path $tempRoot 'smartskip.json') -Encoding utf8
            '{}' | Set-Content -LiteralPath (Join-Path $tempRoot 'devices.json') -Encoding utf8

            $config = Import-VideoArchiveConfig -ProjectRoot $tempRoot -PresetName 'Balanced'

            $config.Encoder.detectHardwareOnStartup | Should Be $true
            $config.Encoder.alwaysPromptEncoderChoiceWithoutRtx | Should Be $true
            $config.Encoder.alwaysPromptEncoderChoice | Should Be $false
        } finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
