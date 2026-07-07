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
            @{ Name = 'VID_20260705_123141.mp4'; Expected = '2026-07-05T12:31:41' }
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
        }
    }

    It 'returns no date for unsupported file names' {
        $result = Get-VideoDateFromFileName -Path 'random_file.mp4'

        $result.Success | Should Be $false
        $result.Source | Should Be 'None'
        $result.DateTime | Should Be $null
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
