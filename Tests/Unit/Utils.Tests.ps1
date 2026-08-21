Import-Module "$PSScriptRoot\..\..\Modules\Utils.psm1" -Force

Describe 'Utils native JSON invocation' {
    BeforeAll {
        $tempRoot = Join-Path $env:TEMP ('VideoArchiveUtils_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        $warningTool = Join-Path $tempRoot 'warning-json.cmd'
        @'
@echo Warning: diagnostic message 1>&2
@echo {"success":true}
@exit /b 0
'@ | Set-Content -LiteralPath $warningTool -Encoding ascii
    }

    AfterAll {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }

    It 'keeps stderr warnings out of JSON stdout' {
        $json = Invoke-VideoArchiveJsonTool `
            -ExecutablePath $warningTool `
            -Arguments @() `
            -Operation 'warning JSON test'

        $parsed = $json | ConvertFrom-Json
        $parsed.success | Should Be $true
    }
}
