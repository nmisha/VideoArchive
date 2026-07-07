Import-Module "$PSScriptRoot\..\..\Modules\DateResolver.psm1" -Force

Describe 'DateResolver' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveDateResolver_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'parses common filename patterns' {
        $examples = @(
            @{ Name = 'VID_20260705_123141.mp4'; Expected = '2026-07-05T12:31:41'; Pattern = 'VID_yyyyMMdd_HHmmss' }
            @{ Name = 'IMG_20260705_123141.mp4'; Expected = '2026-07-05T12:31:41' }
            @{ Name = 'PXL_20260705_123141123.mp4'; Expected = '2026-07-05T12:31:41' }
            @{ Name = '2026-07-05 12.31.41.mp4'; Expected = '2026-07-05T12:31:41' }
            @{ Name = 'WhatsApp Video 2026-07-05 at 12.31.41.mp4'; Expected = '2026-07-05T12:31:41' }
        )

        foreach ($example in $examples) {
            $result = Get-VideoDateFromFileName -Path $example.Name
            $result.Success | Should Be $true
            $result.Source | Should Be 'FileName'
            $result.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') | Should Be $example.Expected
            if ($example.ContainsKey('Pattern')) {
                $result.Pattern | Should Be $example.Pattern
            }
        }
    }

    It 'parses Imou camera filename prefix with milliseconds' {
        $result = Get-VideoDateFromFileName -Path '20260517112753114_F64ACBFPSFC74F9_L_0_L0120517112753.mp4'

        $result.Success | Should Be $true
        $result.Source | Should Be 'FileName'
        $result.Pattern | Should Be 'Imou_yyyyMMddHHmmssfff_prefix'
        $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss.fff') | Should Be '2026-05-17 11:27:53.114'
    }

    It 'parses Insta360 filename with suffix' {
        $result = Get-VideoDateFromFileName -Path 'VID_20250829_234743_10_133.mp4'

        $result.Success | Should Be $true
        $result.Source | Should Be 'FileName'
        $result.Pattern | Should Be 'Insta360_VID_yyyyMMdd_HHmmss_suffix'
        $result.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') | Should Be '2025-08-29T23:47:43'
    }

    It 'keeps plain VID pattern without suffix distinct from Insta360' {
        $result = Get-VideoDateFromFileName -Path 'VID_20250829_234743.mp4'

        $result.Success | Should Be $true
        $result.Source | Should Be 'FileName'
        $result.Pattern | Should Be 'VID_yyyyMMdd_HHmmss'
        $result.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') | Should Be '2025-08-29T23:47:43'
    }

    It 'parses generic embedded 17-digit timestamps only as final fallback' {
        $result = Get-VideoDateFromFileName -Path 'some_export_20260517112753114_clip.mp4'

        $result.Success | Should Be $true
        $result.Source | Should Be 'FileName'
        $result.Pattern | Should Be 'Generic_yyyyMMddHHmmssfff'
        $result.DateTime.ToString('yyyy-MM-dd HH:mm:ss.fff') | Should Be '2026-05-17 11:27:53.114'
    }

    It 'returns no date for unsupported file names' {
        $result = Get-VideoDateFromFileName -Path 'random_file.mp4'

        $result.Success | Should Be $false
        $result.Source | Should Be 'None'
        $result.DateTime | Should Be $null
    }

    It 'returns warning for invalid Imou month values' {
        $result = Get-VideoDateFromFileName -Path '20261317112753114_invalid.mp4'

        $result.Success | Should Be $false
        $result.Source | Should Be 'None'
        $result.DateTime | Should Be $null
        ($result.Warnings -join ' | ') | Should Match 'invalid date'
    }

    It 'returns warning for invalid Imou minute values' {
        $result = Get-VideoDateFromFileName -Path '20260517119953114_invalid.mp4'

        $result.Success | Should Be $false
        $result.Source | Should Be 'None'
        $result.DateTime | Should Be $null
        ($result.Warnings -join ' | ') | Should Match 'invalid date'
    }

    It 'prefers valid metadata date over file name date' {
        $toolPath = Join-Path $tempRoot 'fake-exiftool-metadata.ps1'
        @'
$json = @"
[
  {
    "QuickTime:MediaCreateDate": "2026:07:05 10:00:00"
  }
]
"@
Write-Output $json
exit 0
'@ | Set-Content -LiteralPath $toolPath -Encoding utf8

        $dateConfig = [pscustomobject]@{
            defaultTimezoneOffset = '+03:00'
        }

        $videoPath = Join-Path $tempRoot 'VID_20260705_123141.mp4'
        Set-Content -LiteralPath $videoPath -Value 'x' -Encoding utf8
        $result = Resolve-VideoCaptureDate -Path $videoPath -ExifToolPath $toolPath -DateConfig $dateConfig

        $result.Success | Should Be $true
        $result.Source | Should Be 'Metadata'
        $result.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') | Should Be '2026-07-05T10:00:00'
    }

    It 'falls back to file name when metadata date is invalid' {
        $toolPath = Join-Path $tempRoot 'fake-exiftool-invalid.ps1'
        @'
$json = @"
[
  {
    "QuickTime:MediaCreateDate": "1970:01:01 00:00:00"
  }
]
"@
Write-Output $json
exit 0
'@ | Set-Content -LiteralPath $toolPath -Encoding utf8

        $dateConfig = [pscustomobject]@{
            defaultTimezoneOffset = '+03:00'
        }

        $videoPath = Join-Path $tempRoot 'VID_20260705_123141.mp4'
        Set-Content -LiteralPath $videoPath -Value 'x' -Encoding utf8
        $result = Resolve-VideoCaptureDate -Path $videoPath -ExifToolPath $toolPath -DateConfig $dateConfig

        $result.Success | Should Be $true
        $result.Source | Should Be 'FileName'
        $result.DateTime.ToString('yyyy-MM-ddTHH:mm:ss') | Should Be '2026-07-05T12:31:41'
    }

    It 'returns warnings when neither metadata nor file name contain a valid date' {
        $toolPath = Join-Path $tempRoot 'fake-exiftool-empty.ps1'
        @'
$json = @"
[
  {
  }
]
"@
Write-Output $json
exit 0
'@ | Set-Content -LiteralPath $toolPath -Encoding utf8

        $dateConfig = [pscustomobject]@{
            defaultTimezoneOffset = '+03:00'
        }

        $videoPath = Join-Path $tempRoot 'random_file.mp4'
        Set-Content -LiteralPath $videoPath -Value 'x' -Encoding utf8
        $result = Resolve-VideoCaptureDate -Path $videoPath -ExifToolPath $toolPath -DateConfig $dateConfig

        $result.Success | Should Be $false
        ($result.Warnings -join ' | ') | Should Match 'No valid metadata date found'
        ($result.Warnings -join ' | ') | Should Match 'Filename does not match any supported date pattern'
    }
}
