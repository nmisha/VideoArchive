Set-StrictMode -Version Latest

function New-VideoFileRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$File,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    [pscustomobject]@{
        Path = $File.FullName
        Name = $File.Name
        Directory = $File.DirectoryName
        Extension = $File.Extension.ToLowerInvariant()
        RelativePath = $RelativePath
        SourceRoot = $SourceRoot
        SizeBytes = $File.Length
        CreationTimeUtc = $File.CreationTimeUtc
        LastWriteTimeUtc = $File.LastWriteTimeUtc
    }
}

function Get-VideoFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputPath,

        [Parameter(Mandatory)]
        [string[]]$Extensions
    )

    $resolvedInput = [System.IO.Path]::GetFullPath($InputPath)
    if (-not (Test-Path -LiteralPath $resolvedInput)) {
        throw "Input path not found: $resolvedInput"
    }

    $extensionSet = @{}
    foreach ($extension in $Extensions) {
        $extensionSet[$extension.ToLowerInvariant()] = $true
    }

    $item = Get-Item -LiteralPath $resolvedInput
    if ($item.PSIsContainer) {
        $root = $item.FullName.TrimEnd('\')
        $files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
            $extensionSet.ContainsKey($_.Extension.ToLowerInvariant())
        } | Sort-Object FullName

        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($root.Length).TrimStart('\')
            New-VideoFileRecord -File $file -RelativePath $relativePath -SourceRoot $root
        }
        return
    }

    if (-not $extensionSet.ContainsKey($item.Extension.ToLowerInvariant())) {
        throw "Unsupported input file extension: $($item.Extension)"
    }

    New-VideoFileRecord -File $item -RelativePath $item.Name -SourceRoot $item.DirectoryName
}

Export-ModuleMember -Function Get-VideoFiles
