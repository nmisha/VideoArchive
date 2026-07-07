Import-Module "$PSScriptRoot\..\..\Modules\Metadata.psm1" -Force

Describe 'Metadata' {
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
}
