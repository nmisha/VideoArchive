Set-StrictMode -Version Latest

function Initialize-VideoArchiveLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogRoot
    )

    if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    }

    $runId = Get-Date -Format 'yyyyMMdd_HHmmss'
    $basePath = Join-Path -Path $LogRoot -ChildPath "VideoArchive_$runId"
    $logger = [pscustomobject]@{
        RunId = $runId
        TxtPath = "$basePath.txt"
        CsvPath = "$basePath.csv"
        JsonlPath = "$basePath.jsonl"
    }

    New-Item -ItemType File -Path $logger.TxtPath -Force | Out-Null
    return $logger
}

function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Logger,

        [Parameter(Mandatory)]
        [string]$Message
    )

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $Logger.TxtPath -Value $line
}

function Write-LogRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Logger,

        [Parameter(Mandatory)]
        [psobject]$Record
    )

    $textLine = '[{0}] {1} | {2} | {3}' -f (
        Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ), $Record.Action, $Record.SourcePath, $Record.Reason
    Add-Content -LiteralPath $Logger.TxtPath -Value $textLine

    if (-not (Test-Path -LiteralPath $Logger.CsvPath -PathType Leaf)) {
        $Record | Export-Csv -LiteralPath $Logger.CsvPath -NoTypeInformation -Encoding UTF8
    } else {
        $Record | Export-Csv -LiteralPath $Logger.CsvPath -NoTypeInformation -Append -Encoding UTF8
    }

    $jsonLine = $Record | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath $Logger.JsonlPath -Value $jsonLine
}

Export-ModuleMember -Function Initialize-VideoArchiveLogger, Write-LogMessage, Write-LogRecord
