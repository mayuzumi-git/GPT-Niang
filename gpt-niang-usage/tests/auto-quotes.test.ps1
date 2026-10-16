param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $appDir 'widget.ps1'),[Text.Encoding]::UTF8)
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ($parseErrors|Out-String)}
$ease=$ast.Find({param($n)$n-is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('public sealed class GptBezierEase')},$true)
Add-Type -TypeDefinition $ease.Value -ReferencedAssemblies ([Windows.Media.Animation.EasingFunctionBase].Assembly.Location),([Windows.Freezable].Assembly.Location)
foreach($definition in $ast.FindAll({param($n)$n-is [Management.Automation.Language.FunctionDefinitionAst]},$true)){
  . ([ScriptBlock]::Create($definition.Extent.Text))
}
. (Join-Path $appDir 'runtime\quotes.ps1')
foreach($file in @('quote-layout.ps1','color-theme.ps1','update-ui.ps1')){
  . ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir ('runtime\'+$file)),[Text.Encoding]::UTF8)))
}
Initialize-WidgetQuoteLayouts $appDir
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
function Pump-Animations([int]$Milliseconds){
  $frame=[Windows.Threading.DispatcherFrame]::new()
  $timer=[Windows.Threading.DispatcherTimer]::new()
  $timer.Interval=[TimeSpan]::FromMilliseconds($Milliseconds);$timer.Tag=$frame
  $timer.Add_Tick({param($sender,$event)$sender.Stop();$sender.Tag.Continue=$false})
  $timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
}
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-auto-quotes-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $script:dataDir
$settingsFile=Join-Path $script:dataDir 'settings.json'
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $appDir 'widget.xaml'),[Text.Encoding]::UTF8))
$script:window.Opacity=0;$script:window.IsHitTestVisible=$false
$script:ui=@{}
foreach($match in [regex]::Matches([IO.File]::ReadAllText((Join-Path $appDir 'widget.xaml')),'x:Name="([^"]+)"')){
  $name=$match.Groups[1].Value;$script:ui[$name]=$script:window.FindName($name)
}
$script:context=[Windows.Controls.ContextMenu]::new()
$script:autoQuotesOn=$true;$script:autoQuoteNextAt=0;$script:autoQuotePressTimer=$null
$script:collapsed=$true;$script:bubbleMode='quota';$script:bubbleEpoch=0;$script:sceneRevision=0
$script:drag=$null;$script:runtimeClosed=$false;$script:quoteEditor=$null;$script:colorTriggerEditor=$null;$script:updateProcess=$null
$script:offsetRight=17;$script:scale=1.4;$script:soundOn=$true
$script:status=$null;$script:closeTimer=$null;$script:sceneTimer=$null;$script:resetPhaseTimer=$null
$refreshFile=Join-Path $script:dataDir 'refresh.flag'
try{
  $script:window.Show()
  $now=100000L
  $delays=@(for($i=0;$i-lt 200;$i++){
    $script:autoQuoteNextAt=0;Tick-AutoQuotes $now
    $delay=$script:autoQuoteNextAt-$now
    if($delay-lt 20000 -or $delay-gt 40000){throw 'Random delay escaped 20-40 seconds'}
    $delay
  })
  if(@($delays|Select-Object -Unique).Count-lt 2){throw 'Intervals are not randomized'}
  $due=$script:autoQuoteNextAt
  Tick-AutoQuotes ($due-1)
  Assert-Equal $script:collapsed $true 'No quote before deadline'
  Tick-AutoQuotes $due
  Assert-Equal $script:collapsed $false 'Due quote opens bubble'
  Assert-Equal $script:bubbleMode quote 'No quota scene flashes before the quote'
  Assert-Equal $script:ui.QuotaText.Visibility Collapsed 'Quota content is hidden'
  Assert-Equal $script:ui.QuoteText.Visibility Visible 'Quote content is visible'
  if(!$script:ui.QuoteText.Tag){throw 'Quote was not drawn from the local pool'}
  Assert-Equal (Test-Path $refreshFile) $false 'Automatic quotes never refresh quota'
  Assert-Equal $script:ui.PressScale.HasAnimatedProperties $true 'Uses real WPF press animation'
  Pump-Animations 130
  if($script:ui.PressScale.ScaleY-ge 0.99){throw 'Character was not visibly pressed'}
  Pump-Animations 500
  Assert-Equal $script:autoQuotePressTimer $null 'Automatic press timer releases itself'
  if([Math]::Abs($script:ui.PressScale.ScaleX-1)-gt 0.001 -or [Math]::Abs($script:ui.PressScale.ScaleY-1)-gt 0.001){throw 'Character did not rebound to its original scale'}
  $lastQuote=$script:ui.QuoteText.Tag
  Tick-Scene ($script:sceneDeadline-1)
  Assert-Equal $script:collapsed $false 'Quote stays for the full display period'
  Tick-Scene $script:sceneDeadline
  Assert-Equal $script:collapsed $true 'Quote closes after five seconds'
  $nextDue=$script:autoQuoteNextAt
  Tick-AutoQuotes $nextDue
  if($script:ui.QuoteText.Tag-ceq $lastQuote){throw 'Automatic quotes repeated consecutively'}
  Hide-Quota;Stop-AutoQuotePress

  # A real click takes over the press. The delayed automatic release must not
  # release a character that is now being held by the user.
  Start-AutoQuotePress
  Pump-Animations 50
  Stop-AutoQuotePress
  $script:drag=@{moved=$false};Animate-Press $true
  Pump-Animations 500
  if([Math]::Abs($script:ui.PressScale.ScaleY-0.88)-gt 0.001){throw 'Automatic release interfered with manual press'}
  $script:drag=$null;Animate-Press $false

  foreach($blocker in @('quota','drag','menu','quote-editor','color-editor','update')){
    $script:collapsed=$true;$script:drag=$null;$script:context=[Windows.Controls.ContextMenu]::new()
    $script:quoteEditor=$null;$script:colorTriggerEditor=$null;$script:updateProcess=$null
    switch($blocker){
      quota {$script:collapsed=$false;$script:bubbleMode='quota'}
      drag {$script:drag=@{moved=$true}}
      menu {$script:context=@{IsOpen=$true}}
      quote-editor {$script:quoteEditor=@{IsVisible=$true}}
      color-editor {$script:colorTriggerEditor=@{IsVisible=$true}}
      update {$script:updateProcess=@{HasExited=$false}}
    }
    $script:autoQuoteNextAt=$now
    Tick-AutoQuotes $now
    Assert-Equal $script:autoQuoteNextAt 0 ('Blocked deadline discarded: '+$blocker)
    Assert-Equal $script:autoQuotePressTimer $null ('No automatic press while busy: '+$blocker)
  }
  $script:collapsed=$true;$script:drag=$null;$script:context=[Windows.Controls.ContextMenu]::new()
  $script:quoteEditor=$null;$script:colorTriggerEditor=$null;$script:updateProcess=$null
  $script:window.Hide();$script:autoQuoteNextAt=$now
  Tick-AutoQuotes ($now+900000)
  Assert-Equal $script:autoQuoteNextAt 0 'Hidden time never queues quotes'
  $script:window.Show();Tick-AutoQuotes ($now+900000)
  if($script:autoQuoteNextAt-lt $now+920000){throw 'Showing the widget must start a fresh interval'}
  Assert-Equal $script:collapsed $true 'Resume never immediately catches up'

  Start-AutoQuotePress;Set-WidgetAutoQuotes $false
  $saved=Get-Content -LiteralPath $settingsFile -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-Equal $saved.autoQuotesOn $false 'Disabled preference is persisted'
  Assert-Equal $saved.right 17 'Saving retains placement'
  Assert-Equal $saved.scale 1.4 'Saving retains size'
  Assert-Equal $saved.soundOn $true 'Saving retains sound preference'
  Tick-AutoQuotes ($now+1800000)
  Assert-Equal $script:autoQuoteNextAt 0 'Disabled feature never schedules'
  Assert-Equal $script:autoQuotePressTimer $null 'Disabling cancels automatic press'
  Set-WidgetAutoQuotes $true;Tick-AutoQuotes $now
  if($script:autoQuoteNextAt-lt $now+20000){throw 'Enabling must start a fresh interval'}
  $script:runtimeClosed=$true;Tick-AutoQuotes $now
  Assert-Equal $script:autoQuoteNextAt 0 'Shutdown cannot schedule quotes'
  $script:runtimeClosed=$false

  # Existing manual clicks must still open and refresh the quota scene.
  Show-Quota
  Assert-Equal $script:bubbleMode quota 'Manual default remains quota'
  Assert-Equal (Test-Path $refreshFile) $true 'Manual quota opening still refreshes'
  Write-Output 'PASS: randomized deadlines, real WPF press/rebound, local quotes, TTL, no extra refresh, manual takeover, busy/hidden/disabled/shutdown states and saved preferences'
}finally{
  Stop-AutoQuotePress
  foreach($timer in @($script:sceneTimer,$script:resetPhaseTimer,$script:closeTimer)){if($timer){$timer.Stop()}}
  $script:window.Close()
  $resolved=[IO.Path]::GetFullPath($script:dataDir)
  $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved)-notlike 'gpt-niang-auto-quotes-*'){throw 'Unsafe auto-quotes test cleanup path'}
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
