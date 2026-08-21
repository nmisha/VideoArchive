Import-Module "$PSScriptRoot\..\..\Modules\ConsoleUI.psm1" -Force

Describe 'ConsoleUI menus' {
    BeforeEach {
        $global:VideoArchiveMenuResponses = New-Object System.Collections.Generic.Queue[string]
        $catalog = [pscustomobject]@{
            DefaultPreset = 'Balanced'
            Presets = @(
                [pscustomobject]@{ Name = 'Archive'; Description = 'Archive'; IsDefault = $false }
                [pscustomobject]@{ Name = 'Balanced'; Description = 'Balanced'; IsDefault = $true }
                [pscustomobject]@{ Name = 'Fast'; Description = 'Fast'; IsDefault = $false }
                [pscustomobject]@{ Name = 'Storage'; Description = 'Storage'; IsDefault = $false }
            )
        }
        Mock Read-Host -ModuleName ConsoleUI { $global:VideoArchiveMenuResponses.Dequeue() }
    }

    AfterEach {
        Remove-Variable VideoArchiveMenuResponses -Scope Global -ErrorAction SilentlyContinue
    }

    It 'selects the fifth Advanced menu item and metadata rotation' {
        foreach ($response in @('5', '1', '2', 'D:\Video\clip.mp4')) { $global:VideoArchiveMenuResponses.Enqueue($response) }

        $selection = Select-VideoArchiveMainMenu -PresetCatalog $catalog

        $selection.Mode | Should Be 'advanced'
        $selection.PresetName | Should Be 'Balanced'
        $selection.Advanced.Operation | Should Be 'rotation'
        $selection.Advanced.RotationMode | Should Be 'metadata'
        $selection.Advanced.RotationDegrees | Should Be 180
        $selection.Advanced.InputPath | Should Be 'D:\Video\clip.mp4'
    }

    It 'selects physical 270-degree rotation' {
        foreach ($response in @('5', '1', '6', 'D:\Video\clip.mov')) { $global:VideoArchiveMenuResponses.Enqueue($response) }

        $selection = Select-VideoArchiveMainMenu -PresetCatalog $catalog

        $selection.Advanced.RotationMode | Should Be 'physical'
        $selection.Advanced.RotationDegrees | Should Be 270
    }

    It 'continues to select a normal preset' {
        $global:VideoArchiveMenuResponses.Enqueue('3')

        $selection = Select-VideoArchiveMainMenu -PresetCatalog $catalog

        $selection.Mode | Should Be 'preset'
        $selection.PresetName | Should Be 'Fast'
    }
}
