Set-StrictMode -Version Latest

function Invoke-VideoArchiveJsonTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutablePath,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$Operation
    )

    $stdout = New-Object System.Collections.Generic.List[string]
    $stderr = New-Object System.Collections.Generic.List[string]
    $previousErrorActionPreference = $ErrorActionPreference

    try {
        # Windows PowerShell represents redirected native stderr lines as
        # ErrorRecord instances. Keep them out of the JSON stdout stream.
        $ErrorActionPreference = 'Continue'
        & $ExecutablePath @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $stderr.Add($_.ToString())
            } else {
                $stdout.Add($_.ToString())
            }
        }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $stdoutText = $stdout -join [Environment]::NewLine
    $stderrText = $stderr -join [Environment]::NewLine

    if ($exitCode -ne 0) {
        $details = @($stderrText, $stdoutText) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 1
        throw "$Operation failed with exit code $exitCode. $details"
    }

    if ([string]::IsNullOrWhiteSpace($stdoutText)) {
        throw "$Operation returned no JSON output. $stderrText"
    }

    if (-not [string]::IsNullOrWhiteSpace($stderrText)) {
        Write-Verbose ("{0} warning: {1}" -f $Operation, $stderrText)
    }

    return $stdoutText
}

Export-ModuleMember -Function Invoke-VideoArchiveJsonTool
