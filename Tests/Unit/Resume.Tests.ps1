Import-Module "$PSScriptRoot\..\..\Modules\Resume.psm1" -Force

Describe 'Resume' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveResume_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        $logsRoot = Join-Path $tempRoot 'Logs'
        New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'resolves the latest JSONL log when ResumeFrom is not provided' {
        $older = Join-Path $logsRoot 'VideoArchive_20260707_100000.jsonl'
        $latest = Join-Path $logsRoot 'VideoArchive_20260707_100100.jsonl'
        Set-Content -LiteralPath $older -Value '{}' -Encoding utf8
        Start-Sleep -Milliseconds 50
        Set-Content -LiteralPath $latest -Value '{}' -Encoding utf8

        $result = Resolve-ResumeLogPath -LogRoot $logsRoot

        $result | Should Be $latest
    }

    It 'skips previously encoded validated files in unfinished mode' {
        $sourceFile = Join-Path $tempRoot 'encoded_source.mp4'
        $outputFile = Join-Path $tempRoot 'encoded_output.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $sourceItem = Get-Item -LiteralPath $sourceFile
        $recordPath = Join-Path $logsRoot 'encoded_resume.jsonl'
        $record = [pscustomobject]@{
            SourcePath = $sourceFile
            OutputPath = $outputFile
            Action = 'Encoded'
            ValidationSuccess = $true
            DryRun = $false
            PresetName = 'Balanced'
            SourceFileSizeBytes = $sourceItem.Length
            SourceLastWriteTimeUtc = $sourceItem.LastWriteTimeUtc.ToString('o')
            SourceCreationTimeUtc = $sourceItem.CreationTimeUtc.ToString('o')
        } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8

        $fileRecord = [pscustomobject]@{
            Path = $sourceFile
            RelativePath = 'encoded_source.mp4'
            SizeBytes = $sourceItem.Length
            LastWriteTimeUtc = $sourceItem.LastWriteTimeUtc
            CreationTimeUtc = $sourceItem.CreationTimeUtc
        }

        $plan = Get-ResumePlan -Files @($fileRecord) -ResumeLogPath $recordPath -ResumeMode unfinished -PresetName 'Balanced'

        $plan.ScheduledFiles.Count | Should Be 0
        $plan.SkippedFiles.Count | Should Be 1
        $plan.SkippedFiles[0].SkipCategory | Should Be 'ResumeCompleted'
    }

    It 'reprocesses failed files in failed mode' {
        $sourceFile = Join-Path $tempRoot 'failed_source.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        $sourceItem = Get-Item -LiteralPath $sourceFile

        $recordPath = Join-Path $logsRoot 'failed_resume.jsonl'
        $record = [pscustomobject]@{
            SourcePath = $sourceFile
            OutputPath = 'X:\out.mp4'
            Action = 'Failed'
            ValidationSuccess = $false
            DryRun = $false
            PresetName = 'Balanced'
            SourceFileSizeBytes = $sourceItem.Length
            SourceLastWriteTimeUtc = $sourceItem.LastWriteTimeUtc.ToString('o')
            SourceCreationTimeUtc = $sourceItem.CreationTimeUtc.ToString('o')
        } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8

        $fileRecord = [pscustomobject]@{
            Path = $sourceFile
            RelativePath = 'failed_source.mp4'
            SizeBytes = $sourceItem.Length
            LastWriteTimeUtc = $sourceItem.LastWriteTimeUtc
            CreationTimeUtc = $sourceItem.CreationTimeUtc
        }

        $plan = Get-ResumePlan -Files @($fileRecord) -ResumeLogPath $recordPath -ResumeMode failed -PresetName 'Balanced'

        $plan.ScheduledFiles.Count | Should Be 1
        $plan.SkippedFiles.Count | Should Be 0
    }

    It 'does not treat encoded records with missing output as completed' {
        $sourceFile = Join-Path $tempRoot 'missing_output_source.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        $sourceItem = Get-Item -LiteralPath $sourceFile

        $recordPath = Join-Path $logsRoot 'missing_output_resume.jsonl'
        $record = [pscustomobject]@{
            SourcePath = $sourceFile
            OutputPath = (Join-Path $tempRoot 'does_not_exist.mp4')
            Action = 'Encoded'
            ValidationSuccess = $true
            DryRun = $false
            PresetName = 'Balanced'
            SourceFileSizeBytes = $sourceItem.Length
            SourceLastWriteTimeUtc = $sourceItem.LastWriteTimeUtc.ToString('o')
            SourceCreationTimeUtc = $sourceItem.CreationTimeUtc.ToString('o')
        } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8

        $fileRecord = [pscustomobject]@{
            Path = $sourceFile
            RelativePath = 'missing_output_source.mp4'
            SizeBytes = $sourceItem.Length
            LastWriteTimeUtc = $sourceItem.LastWriteTimeUtc
            CreationTimeUtc = $sourceItem.CreationTimeUtc
        }

        $plan = Get-ResumePlan -Files @($fileRecord) -ResumeLogPath $recordPath -ResumeMode unfinished -PresetName 'Balanced'

        $plan.ScheduledFiles.Count | Should Be 1
        $plan.SkippedFiles.Count | Should Be 0
    }

    It 'ignores stale resume records when source fingerprint changed' {
        $sourceFile = Join-Path $tempRoot 'changed_source.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        $sourceItem = Get-Item -LiteralPath $sourceFile
        $outputFile = Join-Path $tempRoot 'changed_output.mp4'
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8

        $recordPath = Join-Path $logsRoot 'stale_resume.jsonl'
        $record = [pscustomobject]@{
            SourcePath = $sourceFile
            OutputPath = $outputFile
            Action = 'Encoded'
            ValidationSuccess = $true
            DryRun = $false
            PresetName = 'Balanced'
            SourceFileSizeBytes = $sourceItem.Length + 10
            SourceLastWriteTimeUtc = $sourceItem.LastWriteTimeUtc.ToString('o')
            SourceCreationTimeUtc = $sourceItem.CreationTimeUtc.ToString('o')
        } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8

        $fileRecord = [pscustomobject]@{
            Path = $sourceFile
            RelativePath = 'changed_source.mp4'
            SizeBytes = $sourceItem.Length
            LastWriteTimeUtc = $sourceItem.LastWriteTimeUtc
            CreationTimeUtc = $sourceItem.CreationTimeUtc
        }

        $plan = Get-ResumePlan -Files @($fileRecord) -ResumeLogPath $recordPath -ResumeMode unfinished -PresetName 'Balanced'

        $plan.ScheduledFiles.Count | Should Be 1
        $plan.SkippedFiles.Count | Should Be 0
    }

    It 'does not reuse completed files from a different preset' {
        $sourceFile = Join-Path $tempRoot 'preset_source.mp4'
        $outputFile = Join-Path $tempRoot 'preset_output.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        Set-Content -LiteralPath $outputFile -Value 'output' -Encoding utf8
        $sourceItem = Get-Item -LiteralPath $sourceFile

        $recordPath = Join-Path $logsRoot 'preset_resume.jsonl'
        $record = [pscustomobject]@{
            SourcePath = $sourceFile
            OutputPath = $outputFile
            Action = 'Encoded'
            ValidationSuccess = $true
            DryRun = $false
            PresetName = 'Fast'
            SourceFileSizeBytes = $sourceItem.Length
            SourceLastWriteTimeUtc = $sourceItem.LastWriteTimeUtc.ToString('o')
            SourceCreationTimeUtc = $sourceItem.CreationTimeUtc.ToString('o')
        } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8

        $fileRecord = [pscustomobject]@{
            Path = $sourceFile
            RelativePath = 'preset_source.mp4'
            SizeBytes = $sourceItem.Length
            LastWriteTimeUtc = $sourceItem.LastWriteTimeUtc
            CreationTimeUtc = $sourceItem.CreationTimeUtc
        }

        $plan = Get-ResumePlan -Files @($fileRecord) -ResumeLogPath $recordPath -ResumeMode unfinished -PresetName 'Balanced'

        $plan.ScheduledFiles.Count | Should Be 1
        $plan.SkippedFiles.Count | Should Be 0
    }

    It 'skips files without failed history in failed mode' {
        $sourceFile = Join-Path $tempRoot 'new_file.mp4'
        Set-Content -LiteralPath $sourceFile -Value 'source' -Encoding utf8
        $sourceItem = Get-Item -LiteralPath $sourceFile
        $recordPath = Join-Path $logsRoot 'empty_resume.jsonl'
        Set-Content -LiteralPath $recordPath -Value '' -Encoding utf8

        $fileRecord = [pscustomobject]@{
            Path = $sourceFile
            RelativePath = 'new_file.mp4'
            SizeBytes = $sourceItem.Length
            LastWriteTimeUtc = $sourceItem.LastWriteTimeUtc
            CreationTimeUtc = $sourceItem.CreationTimeUtc
        }

        $plan = Get-ResumePlan -Files @($fileRecord) -ResumeLogPath $recordPath -ResumeMode failed -PresetName 'Balanced'

        $plan.ScheduledFiles.Count | Should Be 0
        $plan.SkippedFiles.Count | Should Be 1
        $plan.SkippedFiles[0].SkipCategory | Should Be 'ResumeNoFailedRecord'
    }
}
