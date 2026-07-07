Import-Module "$PSScriptRoot\..\..\Modules\Validator.psm1" -Force

Describe 'Validator' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveValidator_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'passes for preserved HDR parameters and timestamps' {
        $sourceFile = Join-Path $tempRoot 'source.mp4'
        $outputFile = Join-Path $tempRoot 'output.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputItem = Get-Item -LiteralPath $outputFile
        $sourceItem.CreationTime = [datetime]'2026-07-05T12:00:00'
        $sourceItem.LastWriteTime = [datetime]'2026-07-05T12:01:00'
        $sourceItem.LastAccessTime = [datetime]'2026-07-05T12:02:00'
        $outputItem.CreationTime = $sourceItem.CreationTime
        $outputItem.LastWriteTime = $sourceItem.LastWriteTime
        $outputItem.LastAccessTime = $sourceItem.LastAccessTime

        $sourceInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            Rotation = 90
            IsHdr = $true
            HdrType = 'HDR Vivid'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $outputInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            Rotation = 90
            IsHdr = $true
            HdrType = 'HLG'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $sourceMetadata = [pscustomobject]@{
            DateTaken = '2026-07-05T12:03:00'
            GpsLatitude = 55.7558
            GpsLongitude = 37.6176
            HasGps = $true
        }

        $outputMetadata = [pscustomobject]@{
            DateTaken = '2026-07-05T12:03:00'
            QuickTimeMediaCreateDate = '2026-07-05T12:03:01'
            QuickTimeCreateDate = '2026-07-05T12:03:01'
            GpsLatitude = 55.7558
            GpsLongitude = 37.6176
            HasGps = $true
        }

        $captureDateResult = [pscustomobject]@{
            Success = $true
            DateTime = [datetime]'2026-07-05T12:03:00'
            Source = 'Metadata'
            Pattern = 'QuickTime:MediaCreateDate'
            Warnings = @()
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile -ValidateTimestamps -SourceMetadata $sourceMetadata -OutputMetadata $outputMetadata -CaptureDateResult $captureDateResult

        $result.Success | Should Be $true
        $result.Errors.Count | Should Be 0
        ($result.Warnings -join ' | ') | Should Match 'HDR Vivid metadata were not preserved'
    }

    It 'passes when LastAccessTime differs within tolerance' {
        $sourceFile = Join-Path $tempRoot 'source_tolerant.mp4'
        $outputFile = Join-Path $tempRoot 'output_tolerant.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputItem = Get-Item -LiteralPath $outputFile
        $sourceItem.CreationTime = [datetime]'2026-07-05T12:00:00'
        $sourceItem.LastWriteTime = [datetime]'2026-07-05T12:01:00'
        $sourceItem.LastAccessTime = [datetime]'2026-07-05T12:02:00'
        $outputItem.CreationTime = $sourceItem.CreationTime
        $outputItem.LastWriteTime = $sourceItem.LastWriteTime
        $outputItem.LastAccessTime = $sourceItem.LastAccessTime.AddSeconds(1)

        $timestampErrors = Test-FileTimestampsPreserved -SourceFile $sourceFile -OutputFile $outputFile

        $timestampErrors.Count | Should Be 0
    }

    It 'passes when CreationTime and LastWriteTime differ within tolerance' {
        $sourceFile = Join-Path $tempRoot 'source_time_tolerant.mp4'
        $outputFile = Join-Path $tempRoot 'output_time_tolerant.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputItem = Get-Item -LiteralPath $outputFile
        $sourceItem.CreationTime = [datetime]'2026-07-05T12:00:00'
        $sourceItem.LastWriteTime = [datetime]'2026-07-05T12:01:00'
        $sourceItem.LastAccessTime = [datetime]'2026-07-05T12:02:00'
        $outputItem.CreationTime = $sourceItem.CreationTime.AddSeconds(1)
        $outputItem.LastWriteTime = $sourceItem.LastWriteTime.AddSeconds(1)
        $outputItem.LastAccessTime = $sourceItem.LastAccessTime

        $timestampErrors = Test-FileTimestampsPreserved -SourceFile $sourceFile -OutputFile $outputFile

        $timestampErrors.Count | Should Be 0
    }

    It 'passes when FPS delta is within tolerance' {
        $sourceFile = Join-Path $tempRoot 'source_fps_ok.mp4'
        $outputFile = Join-Path $tempRoot 'output_fps_ok.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.785
            Rotation = 0
            IsHdr = $true
            HdrType = 'HLG'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $outputInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.796
            Rotation = 0
            IsHdr = $true
            HdrType = 'HLG'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile

        $result.Success | Should Be $true
    }

    It 'fails when HDR metadata or timestamps are not preserved' {
        $sourceFile = Join-Path $tempRoot 'source_bad.mp4'
        $outputFile = Join-Path $tempRoot 'output_bad.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputItem = Get-Item -LiteralPath $outputFile
        $sourceItem.CreationTime = [datetime]'2026-07-05T12:00:00'
        $sourceItem.LastWriteTime = [datetime]'2026-07-05T12:01:00'
        $sourceItem.LastAccessTime = [datetime]'2026-07-05T12:02:00'
        $outputItem.CreationTime = [datetime]'2026-07-06T12:00:00'
        $outputItem.LastWriteTime = [datetime]'2026-07-06T12:01:00'
        $outputItem.LastAccessTime = [datetime]'2026-07-06T12:02:00'

        $sourceInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            Rotation = 90
            IsHdr = $true
            HdrType = 'HLG'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $outputInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            Rotation = 0
            IsHdr = $false
            HdrType = 'SDR'
            BitDepth = 10
            Transfer = 'BT.709'
            Primaries = 'BT.709'
            Matrix = 'BT.709'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'PCM'
            AudioChannels = 1
            AudioTracks = @([pscustomobject]@{ Codec = 'PCM'; Channels = 1 })
        }

        $sourceMetadata = [pscustomobject]@{
            DateTaken = '2026-07-05T12:03:00'
            GpsLatitude = 55.7558
            GpsLongitude = 37.6176
            HasGps = $true
        }

        $outputMetadata = [pscustomobject]@{
            DateTaken = '2026-07-06T12:03:00'
            GpsLatitude = $null
            GpsLongitude = $null
            HasGps = $false
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile -ValidateTimestamps -SourceMetadata $sourceMetadata -OutputMetadata $outputMetadata

        $result.Success | Should Be $false
        ($result.Errors -join ' | ') | Should Match 'HDR source became SDR'
        ($result.Errors -join ' | ') | Should Match 'CreationTime mismatch'
        ($result.Errors -join ' | ') | Should Match 'Rotation mismatch'
        ($result.Errors -join ' | ') | Should Match 'Audio codec mismatch'
        ($result.Errors -join ' | ') | Should Match 'Audio channels mismatch'
        ($result.Errors -join ' | ') | Should Match 'GPS metadata missing in output'
        ($result.Errors -join ' | ') | Should Match 'DateTaken mismatch'
    }

    It 'fails when LastAccessTime exceeds tolerance' {
        $sourceFile = Join-Path $tempRoot 'source_access_bad.mp4'
        $outputFile = Join-Path $tempRoot 'output_access_bad.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputItem = Get-Item -LiteralPath $outputFile
        $sourceItem.LastAccessTime = [datetime]'2026-07-05T12:02:00'
        $outputItem.LastAccessTime = $sourceItem.LastAccessTime.AddSeconds(5)

        $timestampErrors = Test-FileTimestampsPreserved -SourceFile $sourceFile -OutputFile $outputFile

        ($timestampErrors -join ' | ') | Should Match 'LastAccessTime mismatch'
    }

    It 'fails when CreationTime exceeds tolerance' {
        $sourceFile = Join-Path $tempRoot 'source_creation_bad.mp4'
        $outputFile = Join-Path $tempRoot 'output_creation_bad.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputItem = Get-Item -LiteralPath $outputFile
        $sourceItem.CreationTime = [datetime]'2026-07-05T12:00:00'
        $sourceItem.LastWriteTime = [datetime]'2026-07-05T12:01:00'
        $sourceItem.LastAccessTime = [datetime]'2026-07-05T12:02:00'
        $outputItem.CreationTime = $sourceItem.CreationTime.AddSeconds(5)
        $outputItem.LastWriteTime = $sourceItem.LastWriteTime
        $outputItem.LastAccessTime = $sourceItem.LastAccessTime

        $timestampErrors = Test-FileTimestampsPreserved -SourceFile $sourceFile -OutputFile $outputFile

        ($timestampErrors -join ' | ') | Should Match 'CreationTime mismatch'
    }

    It 'fails when FPS delta exceeds tolerance' {
        $sourceFile = Join-Path $tempRoot 'source_fps_bad.mp4'
        $outputFile = Join-Path $tempRoot 'output_fps_bad.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            Rotation = 0
            IsHdr = $true
            HdrType = 'HLG'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $outputInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 58.94
            Rotation = 0
            IsHdr = $true
            HdrType = 'HLG'
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile

        $result.Success | Should Be $false
        ($result.Errors -join ' | ') | Should Match 'FPS mismatch'
    }

    It 'fails when resolution differs' {
        $sourceFile = Join-Path $tempRoot 'source_resolution_bad.mp4'
        $outputFile = Join-Path $tempRoot 'output_resolution_bad.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            Rotation = 0
            IsHdr = $false
            HdrType = 'SDR'
            BitDepth = 8
            Transfer = 'BT.709'
            Primaries = 'BT.709'
            Matrix = 'BT.709'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $outputInfo = [pscustomobject]@{
            Width = 1920
            Height = 1080
            Fps = 59.94
            Rotation = 0
            IsHdr = $false
            HdrType = 'SDR'
            BitDepth = 8
            Transfer = 'BT.709'
            Primaries = 'BT.709'
            Matrix = 'BT.709'
            Codec = 'HEVC'
            AudioTrackCount = 1
            AudioCodec = 'AAC'
            AudioChannels = 2
            AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile

        $result.Success | Should Be $false
        ($result.Errors -join ' | ') | Should Match 'Resolution mismatch'
    }

    It 'warns when capture date is missing in non-strict mode' {
        $sourceFile = Join-Path $tempRoot 'source_date_warn.mp4'
        $outputFile = Join-Path $tempRoot 'output_date_warn.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceInfo = [pscustomobject]@{
            Width = 1920; Height = 1080; Fps = 30; Rotation = 0; IsHdr = $false; HdrType = 'SDR'; BitDepth = 8
            Transfer = 'BT.709'; Primaries = 'BT.709'; Matrix = 'BT.709'; Codec = 'HEVC'; AudioTrackCount = 1
            AudioCodec = 'AAC'; AudioChannels = 2; AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }
        $outputInfo = $sourceInfo
        $captureDateResult = [pscustomobject]@{
            Success = $false
            DateTime = $null
            Source = 'None'
            Pattern = $null
            Warnings = @('Capture date could not be determined.', 'Capture date was left empty.')
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile -CaptureDateResult $captureDateResult

        $result.Success | Should Be $true
        ($result.Warnings -join ' | ') | Should Match 'Capture date could not be determined'
    }

    It 'fails when capture date is missing in strict mode' {
        $sourceFile = Join-Path $tempRoot 'source_date_strict.mp4'
        $outputFile = Join-Path $tempRoot 'output_date_strict.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceInfo = [pscustomobject]@{
            Width = 1920; Height = 1080; Fps = 30; Rotation = 0; IsHdr = $false; HdrType = 'SDR'; BitDepth = 8
            Transfer = 'BT.709'; Primaries = 'BT.709'; Matrix = 'BT.709'; Codec = 'HEVC'; AudioTrackCount = 1
            AudioCodec = 'AAC'; AudioChannels = 2; AudioTracks = @([pscustomobject]@{ Codec = 'AAC'; Channels = 2 })
        }
        $outputInfo = $sourceInfo
        $captureDateResult = [pscustomobject]@{
            Success = $false
            DateTime = $null
            Source = 'None'
            Pattern = $null
            Warnings = @('Capture date could not be determined.')
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile -CaptureDateResult $captureDateResult -StrictDateMode $true

        $result.Success | Should Be $false
        ($result.Errors -join ' | ') | Should Match 'strict date mode'
    }
}
