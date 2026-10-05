Import-Module "$PSScriptRoot\..\..\Modules\Metadata.psm1" -Force

Describe 'Metadata' {
    It 'marks a QuickTime-derived DateTaken as UTC while keeping raw container fields' {
        $result = ConvertFrom-ExifToolJson -ExifToolJson '[{"MediaCreateDate":"2026:09:20 08:08:13"}]'
        $result.DateTaken | Should Be '2026-09-20T08:08:13Z'
        $result.QuickTimeMediaCreateDate | Should Be '2026-09-20T08:08:13'
    }
    It 'extracts GPS and Date Taken from ExifTool JSON' {
        $sample = @'
[
  {
    "SourceFile": "D:\\Video\\VID.mp4",
    "DateTimeOriginal": "2026:07:05 12:34:56",
    "GPSLatitude": 55.7558,
    "GPSLongitude": 37.6176
  }
]
'@

        $result = ConvertFrom-ExifToolJson -ExifToolJson $sample -Path 'D:\Video\VID.mp4'

        $result.DateTaken | Should Be '2026-07-05T12:34:56'
        $result.HasGps | Should Be $true
        $result.GpsLatitude | Should Be 55.7558
        $result.GpsLongitude | Should Be 37.6176
    }

    It 'prefers offset-aware date metadata over offset-less values' {
        $sample = @'
[
  {
    "DateTimeOriginal": "2012:09:01 18:08:13",
    "CreationDate": "2012:09:01 22:08:13+04:00"
  }
]
'@

        $result = ConvertFrom-ExifToolJson -ExifToolJson $sample -Path 'D:\Video\VID.mp4'

        $result.DateTaken | Should Be '2012-09-01T22:08:13+04:00'
    }

    It 'writes offset-aware filesystem timestamps as the correct UTC instant' {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveTimestamp_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        try {
            $sourceFile = Join-Path $tempRoot 'source.mts'
            $outputFile = Join-Path $tempRoot 'output.mp4'
            Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
            Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8
            $captureDate = [datetimeoffset]::Parse('2012-09-01T22:08:13+04:00')

            Set-FileSystemTimestamps -SourceFile $sourceFile -DestinationFile $outputFile -FileTimestampMode captureDate -CaptureDate $captureDate.DateTime -CaptureDateTimeOffset $captureDate -HasTimezone

            (Get-Item -LiteralPath $outputFile).CreationTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') | Should Be '2012-09-01T18:08:13Z'
            (Get-Item -LiteralPath $outputFile).LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') | Should Be '2012-09-01T18:08:13Z'
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'preserves an earlier creation time than last-write time' {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveTimestampOrder_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        try {
            $sourceFile = Join-Path $tempRoot 'source.mp4'
            $outputFile = Join-Path $tempRoot 'output.mp4'
            Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
            Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8
            $source = Get-Item -LiteralPath $sourceFile
            $source.LastWriteTimeUtc = [datetime]'2026-07-07T00:00:00Z'
            $source.CreationTimeUtc = [datetime]'2026-07-07T00:00:00Z'
            $source.LastWriteTimeUtc = [datetime]'2026-07-07T00:00:12Z'

            Set-FileSystemTimestamps -SourceFile $sourceFile -DestinationFile $outputFile -FileTimestampMode preserve

            $output = Get-Item -LiteralPath $outputFile
            $output.CreationTimeUtc | Should Be $source.CreationTimeUtc
            $output.LastWriteTimeUtc | Should Be $source.LastWriteTimeUtc
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes capture date and source identity to an MKV sidecar' {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveSidecar_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        try {
            $sourceFile = Join-Path $tempRoot 'source.mts'
            $outputFile = Join-Path $tempRoot 'output.mkv'
            Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding UTF8
            Set-Content -LiteralPath $outputFile -Value 'output' -Encoding UTF8
            $captureDateResult = [pscustomobject]@{
                Success = $true
                DateTime = [datetime]'2012-09-01T22:08:13'
                Source = 'Metadata'
                Pattern = 'DateTimeOriginal'
                Warnings = @()
            }
            $sourceMetadata = [pscustomobject]@{
                DateTaken = '2012-09-01T22:08:13'
                GpsLatitude = 55.7558
                GpsLongitude = 37.6176
            }

            $sidecarPath = Write-VideoMetadataSidecar -SourceFile $sourceFile -OutputFile $outputFile -CaptureDateResult $captureDateResult -SourceMetadata $sourceMetadata
            $sidecar = Get-Content -LiteralPath $sidecarPath -Raw -Encoding UTF8 | ConvertFrom-Json

            $sidecarPath | Should Be ([System.IO.Path]::ChangeExtension($outputFile, '.metadata.json'))
            $sidecar.CaptureDate | Should Be '2012-09-01T22:08:13'
            $sidecar.CaptureDateSource | Should Be 'Metadata'
            $sidecar.CaptureDatePattern | Should Be 'DateTimeOriginal'
            $sidecar.GpsLatitude | Should Be 55.7558
        } finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
