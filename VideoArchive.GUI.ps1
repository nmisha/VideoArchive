Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Join-Path -Path $projectRoot -ChildPath 'Modules'

Import-Module (Join-Path -Path $moduleRoot -ChildPath 'Config.psm1') -Force
Import-Module (Join-Path -Path $moduleRoot -ChildPath 'Gui.psm1') -Force

$config = Import-VideoArchiveConfig -ProjectRoot $projectRoot
$presetDefinitions = Get-VideoArchivePresetDefinitions -ProjectRoot $projectRoot
$queueItems = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$historyItems = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$script:CurrentRun = $null
$script:QueueRunning = $false

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="VideoArchive GUI"
        Width="1480"
        Height="940"
        MinWidth="1240"
        MinHeight="820"
        WindowStartupLocation="CenterScreen"
        Background="#0B1220"
        Foreground="#E5E7EB">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" CornerRadius="18" Padding="20" Margin="0,0,0,16" Background="#111827" BorderBrush="#164E63" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel>
                    <TextBlock Text="VideoArchive GUI" FontSize="28" FontWeight="Bold" Foreground="#67E8F9"/>
                    <TextBlock Text="Queue jobs, tune presets, and monitor archive runs from a desktop workflow." Margin="0,6,0,0" FontSize="14" Foreground="#93C5FD"/>
                </StackPanel>
                <StackPanel Grid.Column="1" HorizontalAlignment="Right">
                    <TextBlock x:Name="TxtHeaderStatus" Text="Idle" FontSize="15" FontWeight="SemiBold" Foreground="#34D399" HorizontalAlignment="Right"/>
                    <TextBlock x:Name="TxtHeaderLog" Text="No active run" Margin="0,6,0,0" FontSize="12" Foreground="#94A3B8" HorizontalAlignment="Right"/>
                </StackPanel>
            </Grid>
        </Border>

        <TabControl Grid.Row="1" Background="#0F172A" BorderThickness="0" Padding="0">
            <TabItem Header="Queue">
                <Grid Margin="12">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="260"/>
                    </Grid.RowDefinitions>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="2.1*"/>
                        <ColumnDefinition Width="1.2*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Row="0" Grid.ColumnSpan="2" CornerRadius="14" Padding="16" Margin="0,0,0,12" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="220"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="140"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="120"/>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>

                            <TextBlock Grid.Row="0" Grid.Column="0" Text="Preset" Margin="0,0,10,8" VerticalAlignment="Center"/>
                            <ComboBox x:Name="CmbPreset" Grid.Row="0" Grid.Column="1" Margin="0,0,16,8" Background="#0F172A" Foreground="#E5E7EB"/>
                            <TextBlock Grid.Row="0" Grid.Column="2" Text="Backend" Margin="0,0,10,8" VerticalAlignment="Center"/>
                            <ComboBox x:Name="CmbBackend" Grid.Row="0" Grid.Column="3" Margin="0,0,16,8" Background="#0F172A" Foreground="#E5E7EB"/>
                            <TextBlock Grid.Row="0" Grid.Column="4" Text="Codec" Margin="0,0,10,8" VerticalAlignment="Center"/>
                            <ComboBox x:Name="CmbCodec" Grid.Row="0" Grid.Column="5" Margin="0,0,16,8" Background="#0F172A" Foreground="#E5E7EB"/>
                            <StackPanel Grid.Row="0" Grid.Column="7" Orientation="Horizontal" HorizontalAlignment="Right">
                                <CheckBox x:Name="ChkForce" Content="Force" Margin="0,0,16,8"/>
                                <CheckBox x:Name="ChkNoSmartSkip" Content="NoSmartSkip" Margin="0,0,16,8"/>
                                <CheckBox x:Name="ChkDryRun" Content="DryRun" Margin="0,0,16,8"/>
                                <CheckBox x:Name="ChkResume" Content="Resume" Margin="0,0,16,8"/>
                                <ComboBox x:Name="CmbResumeMode" Width="110" Margin="0,0,0,8" Background="#0F172A" Foreground="#E5E7EB"/>
                            </StackPanel>

                            <StackPanel Grid.Row="1" Grid.ColumnSpan="8" Orientation="Horizontal">
                                <Button x:Name="BtnAddFiles" Content="Add Files" Width="108" Margin="0,0,10,0" Background="#155E75" Foreground="White"/>
                                <Button x:Name="BtnAddFolder" Content="Add Folder" Width="108" Margin="0,0,10,0" Background="#155E75" Foreground="White"/>
                                <Button x:Name="BtnAddSelection" Content="Add From Path" Width="118" Margin="0,0,10,0" Background="#155E75" Foreground="White"/>
                                <TextBox x:Name="TxtInputPath" Width="420" Margin="0,0,10,0" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <Button x:Name="BtnRemoveSelected" Content="Remove Selected" Width="132" Margin="0,0,10,0" Background="#374151" Foreground="White"/>
                                <Button x:Name="BtnClearQueue" Content="Clear Queue" Width="108" Margin="0,0,10,0" Background="#374151" Foreground="White"/>
                                <Button x:Name="BtnStartQueue" Content="Start Queue" Width="108" Margin="0,0,10,0" Background="#166534" Foreground="White"/>
                                <Button x:Name="BtnStopCurrent" Content="Stop Current" Width="108" Margin="0,0,10,0" Background="#991B1B" Foreground="White"/>
                                <Button x:Name="BtnOpenLogsFolder" Content="Open Logs" Width="96" Background="#1D4ED8" Foreground="White"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <Border Grid.Row="1" Grid.Column="0" CornerRadius="14" Margin="0,0,12,12" Padding="10" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Job Queue" FontSize="18" FontWeight="SemiBold" Foreground="#A5F3FC" Margin="4,0,0,10"/>
                            <DataGrid x:Name="GridQueue"
                                      Grid.Row="1"
                                      AutoGenerateColumns="False"
                                      CanUserAddRows="False"
                                      CanUserDeleteRows="False"
                                      IsReadOnly="True"
                                      HeadersVisibility="Column"
                                      GridLinesVisibility="Horizontal"
                                      Background="#0F172A"
                                      BorderThickness="0"
                                      RowBackground="#0F172A"
                                      AlternatingRowBackground="#111827"
                                      Foreground="#E5E7EB"
                                      BorderBrush="#0F172A"
                                      AllowDrop="True">
                                <DataGrid.Columns>
                                    <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="90"/>
                                    <DataGridTextColumn Header="Preset" Binding="{Binding PresetName}" Width="90"/>
                                    <DataGridTextColumn Header="Backend" Binding="{Binding EncoderBackend}" Width="90"/>
                                    <DataGridTextColumn Header="Codec" Binding="{Binding OutputCodec}" Width="80"/>
                                    <DataGridTextColumn Header="Progress" Binding="{Binding ProgressPercent}" Width="80"/>
                                    <DataGridTextColumn Header="Flags" Binding="{Binding Flags}" Width="160"/>
                                    <DataGridTextColumn Header="Input Path" Binding="{Binding InputPath}" Width="*"/>
                                    <DataGridTextColumn Header="Last Message" Binding="{Binding LastMessage}" Width="250"/>
                                </DataGrid.Columns>
                            </DataGrid>
                        </Grid>
                    </Border>

                    <Border Grid.Row="1" Grid.Column="1" CornerRadius="14" Margin="0,0,0,12" Padding="14" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Progress Dashboard" FontSize="18" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                            <ProgressBar x:Name="BarCurrentJob" Grid.Row="1" Height="22" Margin="0,12,0,10" Minimum="0" Maximum="100" Value="0" Foreground="#22C55E" Background="#1F2937"/>
                            <TextBlock x:Name="TxtDashboardStatus" Grid.Row="2" Text="No active job" FontSize="15" FontWeight="SemiBold" Foreground="#E5E7EB"/>
                            <TextBlock x:Name="TxtDashboardCurrent" Grid.Row="3" Margin="0,6,0,0" Text="Current file: n/a" Foreground="#CBD5E1" TextWrapping="Wrap"/>
                            <TextBlock x:Name="TxtDashboardTelemetry" Grid.Row="4" Margin="0,6,0,0" Text="Telemetry: n/a" Foreground="#FBBF24" TextWrapping="Wrap"/>
                            <TextBlock x:Name="TxtDashboardLog" Grid.Row="5" Margin="0,6,0,12" Text="Log: n/a" Foreground="#93C5FD" TextWrapping="Wrap"/>
                            <Border Grid.Row="6" CornerRadius="10" Background="#020617" BorderBrush="#1E293B" BorderThickness="1" Padding="10">
                                <ScrollViewer VerticalScrollBarVisibility="Auto">
                                    <TextBox x:Name="TxtLiveOutput"
                                             AcceptsReturn="True"
                                             TextWrapping="Wrap"
                                             IsReadOnly="True"
                                             Background="#020617"
                                             Foreground="#D1FAE5"
                                             BorderThickness="0"
                                             FontFamily="Consolas"
                                             FontSize="12"
                                             VerticalScrollBarVisibility="Auto"/>
                                </ScrollViewer>
                            </Border>
                        </Grid>
                    </Border>

                    <Border Grid.Row="2" Grid.ColumnSpan="2" CornerRadius="14" Padding="14" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="1.1*"/>
                                <ColumnDefinition Width="1*"/>
                                <ColumnDefinition Width="1*"/>
                                <ColumnDefinition Width="1*"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0">
                                <TextBlock Text="Drop Zone" FontSize="16" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                                <Border x:Name="DropBorder" Margin="0,12,10,0" BorderBrush="#22D3EE" BorderThickness="2" CornerRadius="12" Padding="16" Background="#082F49" AllowDrop="True">
                                    <TextBlock Text="Drag files or folders here to enqueue archive jobs." TextWrapping="Wrap" Foreground="#E0F2FE" FontSize="15"/>
                                </Border>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Margin="14,0,0,0">
                                <TextBlock Text="Queue Stats" FontSize="16" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                                <TextBlock x:Name="TxtQueueCounts" Margin="0,12,0,0" Text="Queued: 0 | Running: 0 | Done: 0 | Failed: 0" Foreground="#E5E7EB"/>
                                <TextBlock x:Name="TxtQueueSelection" Margin="0,8,0,0" Text="Selected: none" Foreground="#94A3B8" TextWrapping="Wrap"/>
                            </StackPanel>
                            <StackPanel Grid.Column="2" Margin="14,0,0,0">
                                <TextBlock Text="Run Policy" FontSize="16" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                                <TextBlock Margin="0,12,0,0" Text="GUI always passes explicit preset/backend/codec to avoid hidden prompts." Foreground="#E5E7EB" TextWrapping="Wrap"/>
                            </StackPanel>
                            <StackPanel Grid.Column="3" Margin="14,0,0,0">
                                <TextBlock Text="Actions" FontSize="16" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                                <Button x:Name="BtnOpenSelectedLog" Content="Open Selected Log" Margin="0,12,0,0" Background="#1D4ED8" Foreground="White"/>
                                <Button x:Name="BtnRevealSelectedPath" Content="Open Selected Path" Margin="0,10,0,0" Background="#374151" Foreground="White"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <TabItem Header="Presets">
                <Grid Margin="12">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="260"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Border Grid.Column="0" CornerRadius="14" Padding="14" Margin="0,0,12,0" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Preset List" FontSize="18" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                            <ListBox x:Name="ListPresets" Grid.Row="1" Margin="0,12,0,12" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                            <StackPanel Grid.Row="2">
                                <TextBlock Text="Clone to new preset name" Margin="0,0,0,6" Foreground="#94A3B8"/>
                                <TextBox x:Name="TxtPresetCloneName" Margin="0,0,0,8" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <Button x:Name="BtnClonePreset" Content="Clone Selected Preset" Background="#1D4ED8" Foreground="White"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Grid.Column="1" CornerRadius="14" Padding="16" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="180"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Grid.Row="0" Grid.ColumnSpan="2" Text="Preset Editor" FontSize="18" FontWeight="SemiBold" Foreground="#A5F3FC" Margin="0,0,0,14"/>
                                <TextBlock Grid.Row="1" Grid.Column="0" Text="Description" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetDescription" Grid.Row="1" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="2" Grid.Column="0" Text="qvbrHdr" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetQvbrHdr" Grid.Row="2" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="3" Grid.Column="0" Text="qvbrSdr" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetQvbrSdr" Grid.Row="3" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="4" Grid.Column="0" Text="nvPreset" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetNvPreset" Grid.Row="4" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="5" Grid.Column="0" Text="lookahead" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetLookahead" Grid.Row="5" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="6" Grid.Column="0" Text="multipass" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetMultipass" Grid.Row="6" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="7" Grid.Column="0" Text="aqStrength" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetAqStrength" Grid.Row="7" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="8" Grid.Column="0" Text="bFrames" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetBFrames" Grid.Row="8" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <TextBlock Grid.Row="9" Grid.Column="0" Text="refFrames" Margin="0,0,12,10"/>
                                <TextBox x:Name="TxtPresetRefFrames" Grid.Row="9" Grid.Column="1" Margin="0,0,0,10" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155"/>
                                <CheckBox x:Name="ChkPresetSpatialAQ" Grid.Row="10" Grid.ColumnSpan="2" Content="spatialAQ" Margin="0,0,0,10"/>
                                <CheckBox x:Name="ChkPresetTemporalAQ" Grid.Row="11" Grid.ColumnSpan="2" Content="temporalAQ" Margin="0,0,0,10"/>
                                <CheckBox x:Name="ChkPresetAdaptiveI" Grid.Row="12" Grid.ColumnSpan="2" Content="adaptiveI" Margin="0,0,0,10"/>
                                <CheckBox x:Name="ChkPresetAdaptiveB" Grid.Row="13" Grid.ColumnSpan="2" Content="adaptiveB" Margin="0,0,0,10"/>
                                <CheckBox x:Name="ChkPresetStrictGop" Grid.Row="14" Grid.ColumnSpan="2" Content="strictGop" Margin="0,0,0,16"/>
                                <StackPanel Grid.Row="15" Grid.ColumnSpan="2" Orientation="Horizontal">
                                    <Button x:Name="BtnSavePreset" Content="Save Preset" Width="120" Margin="0,0,10,0" Background="#166534" Foreground="White"/>
                                    <Button x:Name="BtnReloadPresets" Content="Reload Presets" Width="120" Background="#374151" Foreground="White"/>
                                </StackPanel>
                            </Grid>
                        </ScrollViewer>
                    </Border>
                </Grid>
            </TabItem>

            <TabItem Header="History">
                <Grid Margin="12">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="340"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>
                    <Border Grid.Column="0" CornerRadius="14" Padding="14" Margin="0,0,12,0" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="Log History" FontSize="18" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                            <ListBox x:Name="ListHistory" Grid.Row="1" Margin="0,12,0,12" Background="#0F172A" Foreground="#E5E7EB" BorderBrush="#334155" DisplayMemberPath="Name"/>
                            <StackPanel Grid.Row="2" Orientation="Horizontal">
                                <Button x:Name="BtnRefreshHistory" Content="Refresh" Width="100" Margin="0,0,10,0" Background="#155E75" Foreground="White"/>
                                <Button x:Name="BtnOpenHistoryFile" Content="Open File" Width="100" Margin="0,0,10,0" Background="#1D4ED8" Foreground="White"/>
                                <Button x:Name="BtnOpenHistoryFolder" Content="Open Folder" Width="100" Background="#374151" Foreground="White"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                    <Border Grid.Column="1" CornerRadius="14" Padding="14" Background="#111827" BorderBrush="#1F2937" BorderThickness="1">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>
                            <TextBlock x:Name="TxtHistoryTitle" Text="Select a log file" FontSize="18" FontWeight="SemiBold" Foreground="#A5F3FC"/>
                            <TextBox x:Name="TxtHistoryContent"
                                     Grid.Row="1"
                                     Margin="0,12,0,0"
                                     AcceptsReturn="True"
                                     TextWrapping="Wrap"
                                     IsReadOnly="True"
                                     Background="#020617"
                                     Foreground="#E5E7EB"
                                     BorderBrush="#1E293B"
                                     FontFamily="Consolas"
                                     FontSize="12"
                                     VerticalScrollBarVisibility="Auto"
                                     HorizontalScrollBarVisibility="Auto"/>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>
        </TabControl>

        <StatusBar Grid.Row="2" Background="#111827" Foreground="#CBD5E1">
            <StatusBarItem>
                <TextBlock x:Name="TxtFooterStatus" Text="Ready"/>
            </StatusBarItem>
        </StatusBar>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$namedControls = @(
    'TxtHeaderStatus', 'TxtHeaderLog', 'CmbPreset', 'CmbBackend', 'CmbCodec', 'ChkForce', 'ChkNoSmartSkip',
    'ChkDryRun', 'ChkResume', 'CmbResumeMode', 'BtnAddFiles', 'BtnAddFolder', 'BtnAddSelection', 'TxtInputPath',
    'BtnRemoveSelected', 'BtnClearQueue', 'BtnStartQueue', 'BtnStopCurrent', 'BtnOpenLogsFolder', 'GridQueue',
    'BarCurrentJob', 'TxtDashboardStatus', 'TxtDashboardCurrent', 'TxtDashboardTelemetry', 'TxtDashboardLog',
    'TxtLiveOutput', 'DropBorder', 'TxtQueueCounts', 'TxtQueueSelection', 'BtnOpenSelectedLog', 'BtnRevealSelectedPath',
    'ListPresets', 'TxtPresetCloneName', 'BtnClonePreset', 'TxtPresetDescription', 'TxtPresetQvbrHdr',
    'TxtPresetQvbrSdr', 'TxtPresetNvPreset', 'TxtPresetLookahead', 'TxtPresetMultipass', 'TxtPresetAqStrength',
    'TxtPresetBFrames', 'TxtPresetRefFrames', 'ChkPresetSpatialAQ', 'ChkPresetTemporalAQ', 'ChkPresetAdaptiveI',
    'ChkPresetAdaptiveB', 'ChkPresetStrictGop', 'BtnSavePreset', 'BtnReloadPresets', 'ListHistory',
    'BtnRefreshHistory', 'BtnOpenHistoryFile', 'BtnOpenHistoryFolder', 'TxtHistoryTitle', 'TxtHistoryContent',
    'TxtFooterStatus'
)

foreach ($controlName in $namedControls) {
    Set-Variable -Name $controlName -Value $window.FindName($controlName) -Scope Script
}

$GridQueue.ItemsSource = $queueItems
$ListHistory.ItemsSource = $historyItems

function Set-UiStatus {
    param(
        [string]$Text,
        [string]$Header = $null
    )

    $script:TxtFooterStatus.Text = $Text
    if ($null -ne $Header) {
        $script:TxtHeaderStatus.Text = $Header
    }
}

function Refresh-QueueVisuals {
    $queued = @($queueItems | Where-Object { $_.Status -eq 'Queued' }).Count
    $running = @($queueItems | Where-Object { $_.Status -eq 'Running' }).Count
    $done = @($queueItems | Where-Object { $_.Status -in @('Completed', 'Skipped', 'DryRunCompleted', 'Stopped') }).Count
    $failed = @($queueItems | Where-Object { $_.Status -eq 'Failed' }).Count
    $script:TxtQueueCounts.Text = "Queued: $queued | Running: $running | Done: $done | Failed: $failed"

    $selected = $script:GridQueue.SelectedItem
    if ($null -ne $selected) {
        $script:TxtQueueSelection.Text = "Selected: $($selected.InputPath)"
    } else {
        $script:TxtQueueSelection.Text = 'Selected: none'
    }

    $script:GridQueue.Items.Refresh()
}

function Refresh-HistoryList {
    $historyItems.Clear()
    foreach ($file in @(Get-VideoArchiveHistoryFiles -LogRoot $config.Output.LogsFolder)) {
        [void]$historyItems.Add([pscustomobject]@{
            Name = $file.Name
            Path = $file.FullName
            LastWriteTime = $file.LastWriteTime
            SizeKb = [math]::Round($file.Length / 1KB, 1)
        })
    }
}

function Show-HistoryFile {
    param([psobject]$HistoryItem)

    if ($null -eq $HistoryItem) {
        $script:TxtHistoryTitle.Text = 'Select a log file'
        $script:TxtHistoryContent.Text = ''
        return
    }

    $script:TxtHistoryTitle.Text = "$($HistoryItem.Name) | $($HistoryItem.LastWriteTime)"
    $script:TxtHistoryContent.Text = ((Get-VideoArchiveFileTail -Path $HistoryItem.Path -LineCount 400) -join [Environment]::NewLine)
}

function Refresh-PresetList {
    $presetDefinitions = Get-VideoArchivePresetDefinitions -ProjectRoot $projectRoot
    $script:presetDefinitions = $presetDefinitions
    $presetNames = @($presetDefinitions.PSObject.Properties.Name)

    $script:CmbPreset.ItemsSource = $null
    $script:CmbPreset.ItemsSource = $presetNames
    if ($presetNames -contains $config.PresetName) {
        $script:CmbPreset.SelectedItem = $config.PresetName
    } elseif ($presetNames.Count -gt 0) {
        $script:CmbPreset.SelectedIndex = 0
    }

    $script:ListPresets.ItemsSource = $null
    $script:ListPresets.ItemsSource = $presetNames
    if ($presetNames.Count -gt 0 -and $null -eq $script:ListPresets.SelectedItem) {
        $script:ListPresets.SelectedIndex = 0
    }
}

function Show-PresetEditor {
    param([string]$PresetName)

    if ([string]::IsNullOrWhiteSpace($PresetName)) {
        return
    }

    $preset = $script:presetDefinitions.PSObject.Properties[$PresetName]
    if ($null -eq $preset) {
        return
    }

    $value = $preset.Value
    $script:TxtPresetDescription.Text = [string]$value.description
    $script:TxtPresetQvbrHdr.Text = [string]$value.qvbrHdr
    $script:TxtPresetQvbrSdr.Text = [string]$value.qvbrSdr
    $script:TxtPresetNvPreset.Text = [string]$value.nvPreset
    $script:TxtPresetLookahead.Text = [string]$value.lookahead
    $script:TxtPresetMultipass.Text = [string]$value.multipass
    $script:TxtPresetAqStrength.Text = [string]$value.aqStrength
    $script:TxtPresetBFrames.Text = [string]$value.bFrames
    $script:TxtPresetRefFrames.Text = [string]$value.refFrames
    $script:ChkPresetSpatialAQ.IsChecked = [bool]$value.spatialAQ
    $script:ChkPresetTemporalAQ.IsChecked = [bool]$value.temporalAQ
    $script:ChkPresetAdaptiveI.IsChecked = [bool]$value.adaptiveI
    $script:ChkPresetAdaptiveB.IsChecked = [bool]$value.adaptiveB
    $script:ChkPresetStrictGop.IsChecked = [bool]$value.strictGop
}

function Save-SelectedPreset {
    $presetName = [string]$script:ListPresets.SelectedItem
    if ([string]::IsNullOrWhiteSpace($presetName)) {
        throw 'Select a preset first.'
    }

    $presetProperty = $script:presetDefinitions.PSObject.Properties[$presetName]
    if ($null -eq $presetProperty) {
        throw "Preset '$presetName' was not found."
    }

    $presetProperty.Value.description = [string]$script:TxtPresetDescription.Text
    $presetProperty.Value.qvbrHdr = [int]$script:TxtPresetQvbrHdr.Text
    $presetProperty.Value.qvbrSdr = [int]$script:TxtPresetQvbrSdr.Text
    $presetProperty.Value.nvPreset = [string]$script:TxtPresetNvPreset.Text
    $presetProperty.Value.lookahead = [int]$script:TxtPresetLookahead.Text
    $presetProperty.Value.multipass = [string]$script:TxtPresetMultipass.Text
    $presetProperty.Value.aqStrength = [int]$script:TxtPresetAqStrength.Text
    $presetProperty.Value.bFrames = [int]$script:TxtPresetBFrames.Text
    $presetProperty.Value.refFrames = [int]$script:TxtPresetRefFrames.Text
    $presetProperty.Value.spatialAQ = [bool]$script:ChkPresetSpatialAQ.IsChecked
    $presetProperty.Value.temporalAQ = [bool]$script:ChkPresetTemporalAQ.IsChecked
    $presetProperty.Value.adaptiveI = [bool]$script:ChkPresetAdaptiveI.IsChecked
    $presetProperty.Value.adaptiveB = [bool]$script:ChkPresetAdaptiveB.IsChecked
    $presetProperty.Value.strictGop = [bool]$script:ChkPresetStrictGop.IsChecked

    Save-VideoArchivePresetDefinitions -ProjectRoot $projectRoot -Presets $script:presetDefinitions
    Refresh-PresetList
    $script:ListPresets.SelectedItem = $presetName
    Show-PresetEditor -PresetName $presetName
    Set-UiStatus -Text "Saved preset '$presetName'." -Header 'Preset Saved'
}

function Clone-SelectedPreset {
    $sourcePreset = [string]$script:ListPresets.SelectedItem
    $targetPreset = [string]$script:TxtPresetCloneName.Text

    if ([string]::IsNullOrWhiteSpace($sourcePreset)) {
        throw 'Select a source preset first.'
    }

    if ([string]::IsNullOrWhiteSpace($targetPreset)) {
        throw 'Enter a new preset name.'
    }

    if ($script:presetDefinitions.PSObject.Properties[$targetPreset]) {
        throw "Preset '$targetPreset' already exists."
    }

    $sourceJson = $script:presetDefinitions.PSObject.Properties[$sourcePreset].Value | ConvertTo-Json -Depth 10
    $cloneValue = $sourceJson | ConvertFrom-Json
    Add-Member -InputObject $script:presetDefinitions -NotePropertyName $targetPreset -NotePropertyValue $cloneValue
    Save-VideoArchivePresetDefinitions -ProjectRoot $projectRoot -Presets $script:presetDefinitions
    Refresh-PresetList
    $script:ListPresets.SelectedItem = $targetPreset
    $script:TxtPresetCloneName.Text = ''
    Show-PresetEditor -PresetName $targetPreset
    Set-UiStatus -Text "Cloned preset '$sourcePreset' to '$targetPreset'." -Header 'Preset Cloned'
}

function Add-QueueItemFromPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    [void]$queueItems.Add(
        (New-VideoArchiveQueueItem `
            -InputPath $Path `
            -PresetName ([string]$script:CmbPreset.SelectedItem) `
            -EncoderBackend ([string]$script:CmbBackend.SelectedItem) `
            -OutputCodec ([string]$script:CmbCodec.SelectedItem) `
            -Force:([bool]$script:ChkForce.IsChecked) `
            -NoSmartSkip:([bool]$script:ChkNoSmartSkip.IsChecked) `
            -DryRun:([bool]$script:ChkDryRun.IsChecked) `
            -Resume:([bool]$script:ChkResume.IsChecked) `
            -ResumeMode ([string]$script:CmbResumeMode.SelectedItem))
    )

    Refresh-QueueVisuals
}

function Add-QueueItemsFromDrop {
    param([string[]]$Paths)

    foreach ($path in @($Paths)) {
        Add-QueueItemFromPath -Path $path
    }

    if (@($Paths).Count -gt 0) {
        Set-UiStatus -Text ("Added {0} path(s) to queue." -f @($Paths).Count) -Header 'Queued'
    }
}

function Update-LiveOutput {
    param(
        [string[]]$Lines,
        [psobject]$Snapshot,
        [string]$LogPath
    )

    $script:TxtLiveOutput.Text = (@($Lines) -join [Environment]::NewLine)
    $script:TxtDashboardStatus.Text = if ($null -ne $script:CurrentRun) { "Status: $($script:CurrentRun.Job.Status)" } else { 'No active job' }
    $script:TxtDashboardCurrent.Text = "Current file: $(if ($Snapshot.CurrentFile) { $Snapshot.CurrentFile } else { 'n/a' })"
    $script:TxtDashboardTelemetry.Text = "Telemetry: $(if ($Snapshot.TelemetryLine) { $Snapshot.TelemetryLine } else { 'n/a' })"
    $script:TxtDashboardLog.Text = "Log: $(if ($LogPath) { $LogPath } else { 'n/a' })"
    $script:BarCurrentJob.Value = [math]::Max(0, [math]::Min(100, [int]$Snapshot.Percent))
}

function Start-QueueJob {
    param([psobject]$Job)

    $transcriptDirectory = Join-Path -Path $projectRoot -ChildPath 'Temp\Gui'
    if (-not (Test-Path -LiteralPath $transcriptDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $transcriptDirectory -Force | Out-Null
    }

    $transcriptPath = Join-Path -Path $transcriptDirectory -ChildPath ("gui_run_{0}.log" -f $Job.Id)
    $scriptPath = Join-Path -Path $projectRoot -ChildPath 'VideoArchive.ps1'
    $argumentList = ConvertTo-VideoArchiveCliArguments -ScriptPath $scriptPath -QueueItem $Job
    $encodedArguments = @($argumentList | ForEach-Object { "'{0}'" -f ($_.Replace("'", "''")) })
    $commandText = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$($transcriptPath.Replace("'", "''"))' -Force | Out-Null
try {
    & powershell.exe $($encodedArguments -join ' ')
} finally {
    Stop-Transcript | Out-Null
}
"@

    $job.Status = 'Running'
    $job.StartedAt = Get-Date
    $job.FinishedAt = $null
    $job.LastMessage = 'Launching background process'
    $job.ProgressPercent = 0
    $job.LogPath = $null
    Refresh-QueueVisuals

    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
        -PassThru `
        -WindowStyle Hidden

    $script:CurrentRun = [pscustomobject]@{
        Process = $process
        Job = $job
        TranscriptPath = $transcriptPath
        LastTail = @()
    }

    $script:TxtHeaderStatus.Text = 'Running'
    $script:TxtHeaderLog.Text = $transcriptPath
    Set-UiStatus -Text ("Started: {0}" -f $Job.InputPath) -Header 'Running'
}

function Complete-CurrentRun {
    if ($null -eq $script:CurrentRun) {
        return
    }

    $job = $script:CurrentRun.Job
    $tail = Get-VideoArchiveFileTail -Path $script:CurrentRun.TranscriptPath -LineCount 400
    $snapshot = Get-VideoArchiveProgressSnapshotFromLines -Lines $tail
    $job.ProgressPercent = [int]$snapshot.Percent
    $job.CurrentFile = $snapshot.CurrentFile
    $job.Encoded = $snapshot.Encoded
    $job.Skipped = $snapshot.Skipped
    $job.Failed = $snapshot.Failed
    $job.DryRunCount = $snapshot.DryRun
    $job.FinishedAt = Get-Date
    $job.LogPath = Find-VideoArchiveLogPathFromLines -Lines $tail

    if ($job.Failed -gt 0 -or $snapshot.LastErrorLine) {
        $job.Status = 'Failed'
        $job.LastMessage = if ($snapshot.LastErrorLine) { $snapshot.LastErrorLine } else { 'Run failed' }
    } elseif ($job.DryRun -or $snapshot.DryRun -gt 0) {
        $job.Status = 'DryRunCompleted'
        $job.LastMessage = 'Dry run completed'
    } elseif ($job.Encoded -gt 0) {
        $job.Status = 'Completed'
        $job.LastMessage = 'Encoding completed'
    } elseif ($job.Skipped -gt 0) {
        $job.Status = 'Skipped'
        $job.LastMessage = 'All files skipped'
    } else {
        $job.Status = 'Completed'
        $job.LastMessage = 'Run finished'
    }

    Update-LiveOutput -Lines $tail -Snapshot $snapshot -LogPath $job.LogPath
    Refresh-QueueVisuals
    Refresh-HistoryList
    $script:TxtHeaderStatus.Text = 'Idle'
    $script:TxtHeaderLog.Text = if ($job.LogPath) { $job.LogPath } else { 'No active run' }
    Set-UiStatus -Text $job.LastMessage -Header $job.Status
    $script:CurrentRun = $null
}

function Start-NextQueuedJob {
    if ($null -ne $script:CurrentRun) {
        return
    }

    $nextJob = @($queueItems | Where-Object { $_.Status -eq 'Queued' } | Select-Object -First 1)
    if (@($nextJob).Count -eq 0) {
        $script:QueueRunning = $false
        Set-UiStatus -Text 'Queue finished.' -Header 'Idle'
        return
    }

    Start-QueueJob -Job $nextJob[0]
}

function Start-QueueProcessing {
    if ($queueItems.Count -eq 0) {
        throw 'Queue is empty.'
    }

    $script:QueueRunning = $true
    Start-NextQueuedJob
}

function Stop-CurrentQueueRun {
    if ($null -eq $script:CurrentRun) {
        return
    }

    try {
        if (-not $script:CurrentRun.Process.HasExited) {
            Stop-Process -Id $script:CurrentRun.Process.Id -Force -ErrorAction Stop
        }
    } catch {
    }

    $script:CurrentRun.Job.Status = 'Stopped'
    $script:CurrentRun.Job.FinishedAt = Get-Date
    $script:CurrentRun.Job.LastMessage = 'Stopped by operator'
    $script:QueueRunning = $false
    Refresh-QueueVisuals
    Set-UiStatus -Text 'Current job was stopped.' -Header 'Stopped'
    $script:CurrentRun = $null
}

$backendItems = @('auto', 'nvenc', 'qsv', 'amf', 'software')
$codecItems = @('hevc', 'auto', 'av1')
$resumeModeItems = @('unfinished', 'failed', 'all')

$CmbBackend.ItemsSource = $backendItems
$CmbBackend.SelectedItem = [string]$config.Encoder.defaultBackend
$CmbCodec.ItemsSource = $codecItems
$defaultCodecForGui = if ([string]::IsNullOrWhiteSpace([string]$config.Encoder.defaultCodec)) { 'hevc' } else { [string]$config.Encoder.defaultCodec }
$CmbCodec.SelectedItem = $defaultCodecForGui
$CmbResumeMode.ItemsSource = $resumeModeItems
$CmbResumeMode.SelectedItem = 'unfinished'

Refresh-PresetList
Refresh-HistoryList
Show-HistoryFile -HistoryItem $null
Show-PresetEditor -PresetName ([string]$ListPresets.SelectedItem)
Refresh-QueueVisuals
Set-UiStatus -Text 'GUI ready.' -Header 'Idle'

$GridQueue.add_SelectionChanged({
    Refresh-QueueVisuals
})

$ListPresets.add_SelectionChanged({
    Show-PresetEditor -PresetName ([string]$script:ListPresets.SelectedItem)
})

$ListHistory.add_SelectionChanged({
    Show-HistoryFile -HistoryItem $script:ListHistory.SelectedItem
})

$BtnReloadPresets.Add_Click({
    Refresh-PresetList
    Show-PresetEditor -PresetName ([string]$script:ListPresets.SelectedItem)
    Set-UiStatus -Text 'Preset list reloaded.' -Header 'Presets'
})

$BtnSavePreset.Add_Click({
    try {
        Save-SelectedPreset
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Preset Save Error', 'OK', 'Error') | Out-Null
    }
})

$BtnClonePreset.Add_Click({
    try {
        Clone-SelectedPreset
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Preset Clone Error', 'OK', 'Error') | Out-Null
    }
})

$BtnAddSelection.Add_Click({
    try {
        Add-QueueItemFromPath -Path $script:TxtInputPath.Text
        $script:TxtInputPath.Text = ''
        Set-UiStatus -Text 'Path added to queue.' -Header 'Queued'
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Queue Error', 'OK', 'Error') | Out-Null
    }
})

$BtnAddFiles.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.CheckFileExists = $true
    $dialog.Filter = 'Video files|*.mp4;*.mov;*.mkv;*.m4v;*.mts;*.m2ts;*.avi;*.wmv;*.webm|All files|*.*'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-QueueItemsFromDrop -Paths $dialog.FileNames
    }
})

$BtnAddFolder.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Add-QueueItemFromPath -Path $dialog.SelectedPath
        Set-UiStatus -Text 'Folder added to queue.' -Header 'Queued'
    }
})

$BtnRemoveSelected.Add_Click({
    $selected = @($GridQueue.SelectedItems)
    foreach ($item in $selected) {
        [void]$queueItems.Remove($item)
    }
    Refresh-QueueVisuals
})

$BtnClearQueue.Add_Click({
    if ($null -ne $script:CurrentRun) {
        [System.Windows.MessageBox]::Show('Stop the current run before clearing the queue.', 'Queue Busy', 'OK', 'Warning') | Out-Null
        return
    }
    $queueItems.Clear()
    Refresh-QueueVisuals
})

$BtnStartQueue.Add_Click({
    try {
        Start-QueueProcessing
    } catch {
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'Queue Start Error', 'OK', 'Error') | Out-Null
    }
})

$BtnStopCurrent.Add_Click({
    Stop-CurrentQueueRun
})

$BtnOpenLogsFolder.Add_Click({
    Start-Process explorer.exe $config.Output.LogsFolder
})

$BtnOpenSelectedLog.Add_Click({
    $selected = $GridQueue.SelectedItem
    if ($null -ne $selected -and -not [string]::IsNullOrWhiteSpace([string]$selected.LogPath) -and (Test-Path -LiteralPath $selected.LogPath -PathType Leaf)) {
        Start-Process explorer.exe $selected.LogPath
    }
})

$BtnRevealSelectedPath.Add_Click({
    $selected = $GridQueue.SelectedItem
    if ($null -ne $selected -and (Test-Path -LiteralPath $selected.InputPath)) {
        Start-Process explorer.exe $selected.InputPath
    }
})

$BtnRefreshHistory.Add_Click({
    Refresh-HistoryList
    Set-UiStatus -Text 'History refreshed.' -Header 'History'
})

$BtnOpenHistoryFile.Add_Click({
    $selected = $ListHistory.SelectedItem
    if ($null -ne $selected) {
        Start-Process explorer.exe $selected.Path
    }
})

$BtnOpenHistoryFolder.Add_Click({
    Start-Process explorer.exe $config.Output.LogsFolder
})

$dropHandler = {
    param($sender, $eventArgs)

    if ($eventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $paths = [string[]]$eventArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
        Add-QueueItemsFromDrop -Paths $paths
        $eventArgs.Handled = $true
    }
}

$dragOverHandler = {
    param($sender, $eventArgs)
    if ($eventArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $eventArgs.Effects = [System.Windows.DragDropEffects]::Copy
    } else {
        $eventArgs.Effects = [System.Windows.DragDropEffects]::None
    }
    $eventArgs.Handled = $true
}

$DropBorder.Add_Drop($dropHandler)
$DropBorder.Add_DragOver($dragOverHandler)
$GridQueue.Add_Drop($dropHandler)
$GridQueue.Add_DragOver($dragOverHandler)

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(1000)
$timer.Add_Tick({
    if ($null -eq $script:CurrentRun) {
        return
    }

    $tail = Get-VideoArchiveFileTail -Path $script:CurrentRun.TranscriptPath -LineCount 400
    $snapshot = Get-VideoArchiveProgressSnapshotFromLines -Lines $tail
    $logPath = Find-VideoArchiveLogPathFromLines -Lines $tail
    if (-not [string]::IsNullOrWhiteSpace($logPath)) {
        $script:CurrentRun.Job.LogPath = $logPath
        $script:TxtHeaderLog.Text = $logPath
    }

    $script:CurrentRun.Job.ProgressPercent = [int]$snapshot.Percent
    $script:CurrentRun.Job.CurrentFile = $snapshot.CurrentFile
    $script:CurrentRun.Job.LastMessage = if ($snapshot.LastErrorLine) { $snapshot.LastErrorLine } elseif ($snapshot.TelemetryLine) { $snapshot.TelemetryLine } elseif ($snapshot.ProgressLine) { $snapshot.ProgressLine } else { 'Running' }
    Update-LiveOutput -Lines $tail -Snapshot $snapshot -LogPath $logPath
    Refresh-QueueVisuals

    if ($script:CurrentRun.Process.HasExited) {
        Complete-CurrentRun
        if ($script:QueueRunning) {
            Start-NextQueuedJob
        }
    }
})
$timer.Start()

$window.Add_Closing({
    $timer.Stop()
    if ($null -ne $script:CurrentRun -and -not $script:CurrentRun.Process.HasExited) {
        $answer = [System.Windows.MessageBox]::Show('A job is still running. Stop it and close the GUI?', 'VideoArchive GUI', 'YesNo', 'Warning')
        if ($answer -eq 'Yes') {
            Stop-CurrentQueueRun
        } else {
            $_.Cancel = $true
        }
    }
})

[void]$window.ShowDialog()
