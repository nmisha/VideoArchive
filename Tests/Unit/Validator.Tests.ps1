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
        Set-Content -LiteralPath $sourceFile -Value 'source'
        Set-Content -LiteralPath $outputFile -Value 'output'

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
            IsHdr = $true
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
        }

        $outputInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            IsHdr = $true
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile -ValidateTimestamps

        $result.Success | Should Be $true
        $result.Errors.Count | Should Be 0
    }

    It 'fails when HDR metadata or timestamps are not preserved' {
        $sourceFile = Join-Path $tempRoot 'source_bad.mp4'
        $outputFile = Join-Path $tempRoot 'output_bad.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source'
        Set-Content -LiteralPath $outputFile -Value 'output'

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
            IsHdr = $true
            BitDepth = 10
            Transfer = 'HLG'
            Primaries = 'BT.2020'
            Matrix = 'BT.2020 non-constant'
            Codec = 'HEVC'
            AudioTrackCount = 1
        }

        $outputInfo = [pscustomobject]@{
            Width = 3840
            Height = 2160
            Fps = 59.94
            IsHdr = $true
            BitDepth = 10
            Transfer = 'BT.709'
            Primaries = 'BT.709'
            Matrix = 'BT.709'
            Codec = 'HEVC'
            AudioTrackCount = 1
        }

        $result = Test-EncodedVideo -SourceFile $sourceFile -SourceInfo $sourceInfo -OutputInfo $outputInfo -OutputFile $outputFile -ValidateTimestamps

        $result.Success | Should Be $false
        ($result.Errors -join ' | ') | Should Match 'HDR transfer mismatch'
        ($result.Errors -join ' | ') | Should Match 'CreationTime mismatch'
    }
}
