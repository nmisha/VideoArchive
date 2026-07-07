param(
    [string]$Path = '.',
    [switch]$Recurse,
    [switch]$Summary
)

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8 = [System.Text.UTF8Encoding]::new($false)
$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$utf16Le = [System.Text.Encoding]::Unicode
$utf16Be = [System.Text.Encoding]::BigEndianUnicode
$cp1251 = [System.Text.Encoding]::GetEncoding(1251)

function Test-ContainsCyrillic {
    param([string]$Text)

    foreach ($character in $Text.ToCharArray()) {
        $codePoint = [int][char]$character
        if ($codePoint -ge 0x0400 -and $codePoint -le 0x04FF) {
            return $true
        }
    }

    return $false
}

function Test-ContainsMojibakePattern {
    param([string]$Text)

    $patterns = @(
        [string][char]0x00D0,
        [string][char]0x00D1,
        [string][char]0x00E2,
        [string][char]0x00C3
    )

    foreach ($pattern in $patterns) {
        if ($Text.Contains($pattern)) {
            return $true
        }
    }

    return $false
}

function Get-DetectedEncoding {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [pscustomobject]@{
            Name = 'utf8-bom'
            Encoding = $utf8Bom
            Bom = 'UTF-8'
            Offset = 3
        }
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [pscustomobject]@{
            Name = 'utf16-le'
            Encoding = $utf16Le
            Bom = 'UTF-16 LE'
            Offset = 2
        }
    }

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [pscustomobject]@{
            Name = 'utf16-be'
            Encoding = $utf16Be
            Bom = 'UTF-16 BE'
            Offset = 2
        }
    }

    try {
        [void]$strictUtf8.GetString($Bytes)
        return [pscustomobject]@{
            Name = 'utf8'
            Encoding = $utf8
            Bom = 'None'
            Offset = 0
        }
    } catch {
        return [pscustomobject]@{
            Name = 'legacy-ansi'
            Encoding = $cp1251
            Bom = 'None'
            Offset = 0
        }
    }
}

function Get-EncodingInfo {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    $detected = Get-DetectedEncoding -Bytes $bytes
    $text = $detected.Encoding.GetString($bytes, [int]$detected.Offset, $bytes.Length - [int]$detected.Offset)

    [pscustomobject]@{
        Path = $FilePath
        Encoding = $detected.Name
        Bom = $detected.Bom
        SizeBytes = $bytes.Length
        HasCyrillic = (Test-ContainsCyrillic -Text $text)
        HasMojibakePattern = (Test-ContainsMojibakePattern -Text $text)
    }
}

function Get-TargetFiles {
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [switch]$Deep
    )

    $resolved = Resolve-Path -LiteralPath $InputPath
    $item = Get-Item -LiteralPath $resolved

    if (-not $item.PSIsContainer) {
        return @($item)
    }

    $extensions = @('.md', '.json', '.txt', '.ps1', '.psm1', '.cmd')
    $specialNames = @('.editorconfig', '.gitattributes')
    $childItems = Get-ChildItem -LiteralPath $item.FullName -File -Recurse:$Deep

    return @(
        $childItems | Where-Object {
            $_.Extension.ToLowerInvariant() -in $extensions -or $_.Name -in $specialNames
        }
    )
}

$files = @(Get-TargetFiles -InputPath $Path -Deep:$Recurse | Sort-Object FullName)
$results = foreach ($file in $files) {
    Get-EncodingInfo -FilePath $file.FullName
}

if ($Summary) {
    $problemResults = @(
        $results | Where-Object {
            $_.Encoding -ne 'utf8' -or
            $_.Bom -ne 'None' -or
            $_.HasMojibakePattern -or
            ($_.Path -match '\.ps1$' -and $_.HasCyrillic -and $_.Encoding -ne 'utf8-bom')
        }
    )

    if ($problemResults.Count -eq 0) {
        Write-Output 'No encoding issues detected.'
    } else {
        $problemResults | Format-Table -AutoSize
    }
} else {
    $results | Format-Table -AutoSize
}
