Import-Module "$PSScriptRoot\..\..\Modules\MediaAnalyzer.psm1" -Force

Describe 'MediaAnalyzer' {
    It 'detects HDR HLG from MediaInfo JSON sample' {
        $sample = @'
{
  "media": {
    "track": [
      {
        "@type": "General",
        "Duration": "12.345"
      },
      {
        "@type": "Video",
        "Format": "HEVC",
        "Width": "3840",
        "Height": "2160",
        "FrameRate": "59.940",
        "BitDepth": "10",
        "BitRate": "77200000",
        "transfer_characteristics": "HLG",
        "colour_primaries": "BT.2020",
        "matrix_coefficients": "BT.2020 non-constant",
        "HDR_Format": "HDR Vivid"
      },
      {
        "@type": "Audio",
        "Format": "AAC"
      }
    ]
  }
}
'@

        $result = ConvertFrom-MediaInfoJson -MediaInfoJson $sample -Path 'D:\Video\VID.mp4' -SourceSizeBytes 104857600

        $result.Codec | Should Be 'HEVC'
        $result.Width | Should Be 3840
        $result.Height | Should Be 2160
        $result.BitDepth | Should Be 10
        $result.BitrateMbps | Should Be 77.2
        $result.IsHdr | Should Be $true
        $result.HdrType | Should Be 'HDR Vivid'
        $result.AudioTrackCount | Should Be 1
    }

    It 'keeps SDR media classified as SDR' {
        $sample = @'
{
  "media": {
    "track": [
      {
        "@type": "General",
        "Duration": "60000"
      },
      {
        "@type": "Video",
        "Format": "AVC",
        "Width": "1920",
        "Height": "1080",
        "FrameRate": "29.970",
        "BitDepth": "8",
        "BitRate": "8500000",
        "transfer_characteristics": "BT.709",
        "colour_primaries": "BT.709",
        "matrix_coefficients": "BT.709"
      }
    ]
  }
}
'@

        $result = ConvertFrom-MediaInfoJson -MediaInfoJson $sample -Path 'D:\Video\SDR.mp4' -SourceSizeBytes 52428800

        $result.Codec | Should Be 'AVC'
        $result.IsHdr | Should Be $false
        $result.HdrType | Should Be $null
        $result.BitDepth | Should Be 8
        $result.DurationSeconds | Should Be 60
    }
}
