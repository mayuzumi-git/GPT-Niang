param([string]$ResultFile)
$ErrorActionPreference='Stop'
$script:appDir=Split-Path $PSScriptRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $script:appDir 'runtime/music.ps1'),[Text.Encoding]::UTF8)))
Initialize-WidgetMusicTypes
Add-Type -TypeDefinition 'public static class RetainedLightMove { public static void Move(int x,int y){} }'
$window=$null;$music=$null
try{
 $window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'widget.xaml')))
 $window.Width=$window.Height=378;$window.Left=$window.Top=-5000
 $girl=$window.FindName('Girl');$girl.Source=[Windows.Media.Imaging.BitmapImage]::new([Uri](Join-Path $script:appDir 'assets/gpt-dragon-niang-bust.png'))
 foreach($name in @('Bubble','Tail','TailNear')){$window.FindName($name).Visibility='Collapsed'}
 $window.Show();$handle=[Windows.Interop.WindowInteropHelper]::new($window).Handle
 $colors=[Windows.Media.Color[]]@([Windows.Media.Colors]::Purple,[Windows.Media.Colors]::Cyan,[Windows.Media.Colors]::Purple)
 $move=[Delegate]::CreateDelegate([Action[int,int]],[RetainedLightMove].GetMethod('Move'))
 $music=[GptMusicVisual]::new($window,$girl,$window.FindName('Bubble'),$move,$colors,$true)
 $music.HostFrame=[Func[int[]]]{return @(0,0,1000,800)}
 $music.Configure($handle,[IntPtr]::Zero,$true,$true,$false,$false,300,300,0,800,1)
 $light=[Windows.Interop.HwndSource]::FromHwnd($music.LampHandle).RootVisual
 $dirty=$light.GetType().GetProperty('NeedsRedraw')
 function Paint-Light {
  $light.Measure([Windows.Size]::new(1000,800));$light.Arrange([Windows.Rect]::new(0,0,1000,800));$light.InvalidateVisual();$light.UpdateLayout()
  $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(1000,800,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($light)
  if($dirty.GetValue($light,$null)){throw 'Paint did not retain the current lighting state'}
 }
 $music.Motion.Phase=2;$music.Motion.Props=1;Paint-Light
 $music.Motion.BeginHold(0,0,52);$music.Motion.Step(.016,$false,$false,0,.5,0);Paint-Light
 for($i=0;$i-lt 60;$i++){
  $music.Motion.MoveHeld(400+$i,500-$i,.016,$i,-$i);$music.Motion.Step(.016,$false,$false,0,.5,0)
  if($dirty.GetValue($light,$null)){throw 'Held character motion invalidated unchanged room lighting'}
 }
 $music.Motion.Release()
 for($i=0;$i-lt 5;$i++){
  $music.Motion.Step(.016,$false,$false,0,.5,0)
  if($dirty.GetValue($light,$null)){throw 'Airborne character motion invalidated unchanged room lighting'}
 }
 $music.Motion.Lamp+=1
 if(!$dirty.GetValue($light,$null)){throw 'Lamp animation did not invalidate lighting'}
 Paint-Light
 $light.Width=1100
 if(!$dirty.GetValue($light,$null)){throw 'Frame resize did not invalidate lighting'}
 $light.Width=1000
 $tiles=$light.GetType().GetField('tiles',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($light)
 if(!$tiles.IsFrozen -or $tiles.Children.Count-ne 180){throw 'Mirror-ball drawing was not retained as one frozen resource'}
 $result=@{passed=$true;unchangedHeldFrames=60;unchangedFlightFrames=5;animatedLightInvalidates=$true;resizeInvalidates=$true;cachedFrozenTiles=$tiles.Children.Count}
 if($ResultFile){[IO.File]::WriteAllText($ResultFile,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
 Write-Output 'PASS: unchanged room lighting retained through pickup/flight; light animation and frame resize invalidate; 180 mirror tiles cached'
}finally{if($music){$music.Dispose()};if($window){$window.Close()}}
