Import-Module "$PSScriptRoot\..\..\Modules\Gui.psm1" -Force

Describe 'GUI helpers' {
    It 'creates queue items with normalized defaults' {
        $item = New-VideoArchiveQueueItem -InputPath '.\README.md' -PresetName 'Balanced'

        $item.PresetName | Should Be 'Balanced'
        $item.EncoderBackend | Should Be 'auto'
        $item.OutputCodec | Should Be 'auto'
        $item.Status | Should Be 'Queued'
        $item.Flags | Should Be 'Default'
    }

    It 'builds CLI arguments from a queue item' {
        $item = [pscustomobject]@{
            InputPath = 'D:\Video'
            PresetName = 'Archive'
            EncoderBackend = 'nvenc'
            OutputCodec = 'hevc'
            Force = $true
            NoSmartSkip = $false
            DryRun = $true
            Resume = $true
            ResumeMode = 'failed'
        }

        $args = ConvertTo-VideoArchiveCliArguments -ScriptPath 'X:\Projects\VideoArchive\VideoArchive.ps1' -QueueItem $item

        ($args -join ' ') | Should Match '-Preset Archive'
        ($args -join ' ') | Should Match '-EncoderBackend nvenc'
        ($args -join ' ') | Should Match '-OutputCodec hevc'
        ($args -contains '-Force') | Should Be $true
        ($args -contains '-DryRun') | Should Be $true
        ($args -contains '-Resume') | Should Be $true
    }

    It 'extracts a log path from console lines' {
        $logPath = Find-VideoArchiveLogPathFromLines -Lines @(
            'Input : D:\Video'
            'Logs  : X:\Projects\VideoArchive\Logs\VideoArchive_20260708_120000.txt'
        )

        $logPath | Should Be 'X:\Projects\VideoArchive\Logs\VideoArchive_20260708_120000.txt'
    }

    It 'parses progress snapshot lines' {
        $snapshot = Get-VideoArchiveProgressSnapshotFromLines -Lines @(
            'Progress: [#####-----] 1/5 (20%) | ETA 16:53 | Avg/File 04:13 | E:1 S:0 F:0 D:0'
            'Current : VID_20260705_123141.mp4'
            'Encoding: 18.8% | 559 frames | FPS 27.80 | ETA 0:01:26 | Elapsed 00:00:22 | E:1 S:0 F:0 D:0'
            'Encoded : 1'
            'Skipped : 0'
            'ResSkip : 0'
            'Failed  : 0'
            'DryRun  : 0'
        )

        $snapshot.Percent | Should Be 20
        $snapshot.CurrentFile | Should Be 'VID_20260705_123141.mp4'
        $snapshot.TelemetryLine | Should Match '^Encoding:'
        $snapshot.Encoded | Should Be 1
    }

    It 'loads and saves preset definitions' {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveGui_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        try {
            @'
{
  "Balanced": {
    "description": "Recommended balance",
    "qvbrHdr": 19
  }
}
'@ | Set-Content -LiteralPath (Join-Path $tempRoot 'presets.json') -Encoding utf8

            $presets = Get-VideoArchivePresetDefinitions -ProjectRoot $tempRoot
            $presets.Balanced.qvbrHdr | Should Be 19

            $presets.Balanced.qvbrHdr = 21
            Save-VideoArchivePresetDefinitions -ProjectRoot $tempRoot -Presets $presets

            $reloaded = Get-VideoArchivePresetDefinitions -ProjectRoot $tempRoot
            $reloaded.Balanced.qvbrHdr | Should Be 21
        } finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
}
