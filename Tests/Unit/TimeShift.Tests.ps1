Import-Module "$PSScriptRoot\..\..\Modules\TimeShift.psm1" -Force

Describe 'Capture time shift' {
    It 'parses positive shifts including more than 24 hours' {
        (ConvertTo-VideoTimeShift '+27:15:30').TotalSeconds | Should Be 98130
    }
    It 'subtracts across a year boundary' {
        ([datetime]'2026-01-01T00:30:00').Add((ConvertTo-VideoTimeShift '-01:30:00')).ToString('s') | Should Be '2025-12-31T23:00:00'
    }
    It 'rejects missing signs, invalid minutes and zero shifts' {
        foreach ($value in @('01:00:00', '+01:60:00', '-00:00:00', 'bad', '+1')) {
            { ConvertTo-VideoTimeShift $value } | Should Throw
        }
    }
    It 'copies every stream and passes a signed-offset date to FFmpeg' {
        $fake = Join-Path $TestDrive 'ffmpeg.ps1'
        @'
$global:TimeShiftArguments = $args
Set-Content -LiteralPath $args[-1] -Value 'media'
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath $fake
        Invoke-TimeShiftRemux -SourcePath 'clip.mp4' -OutputPath (Join-Path $TestDrive 'out.mp4') -CreationTime '2026-01-01T12:00:00Z' -FfmpegPath $fake
        ($global:TimeShiftArguments -join '|') | Should Match '\|-map\|0\|'
        ($global:TimeShiftArguments -join '|') | Should Match '\|-c\|copy\|'
        ($global:TimeShiftArguments -join '|') | Should Match 'creation_time=2026-01-01T12:00:00Z'
        Remove-Variable TimeShiftArguments -Scope Global
    }
    It 'rejects failed remuxes' {
        $fake = Join-Path $TestDrive 'failure.ps1'
        '$global:LASTEXITCODE = 1' | Set-Content -LiteralPath $fake
        { Invoke-TimeShiftRemux -SourcePath 'clip.mp4' -OutputPath (Join-Path $TestDrive 'bad.mp4') -CreationTime '2026-01-01' -FfmpegPath $fake } | Should Throw
    }
}
