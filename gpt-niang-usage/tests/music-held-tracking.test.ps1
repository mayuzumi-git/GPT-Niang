param([string]$ResultFile)
$ErrorActionPreference='Stop'
$script:appDir=Split-Path $PSScriptRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $script:appDir 'runtime/music.ps1'),[Text.Encoding]::UTF8)))
Initialize-WidgetMusicTypes
$samples=0;$maxError=0.0
foreach($dpi in @(1.0,1.5,2.0)){
 foreach($fps in @(30,60,144)){
  $dt=1.0/$fps;$lift=52*$dpi
  $moving=[GptMusicMotion]::new(3000*$dpi,3000*$dpi,10000*$dpi,10000*$dpi,132*$dpi,$dpi)
  $resting=[GptMusicMotion]::new(3000*$dpi,3000*$dpi,10000*$dpi,10000*$dpi,132*$dpi,$dpi)
  $moving.BeginHold(0,0,$lift);$resting.BeginHold(0,0,$lift)
  for($i=1;$i-le $fps;$i++){
   $time=$i*$dt;$dx=250*$dpi*[Math]::Sin(9*$time);$dy=300*$dpi*[Math]::Sin(11*$time)
   $moving.MoveHeld(3000*$dpi+$dx,3000*$dpi-$lift+$dy,$dt,$dx,$dy)
   $resting.MoveHeld(3000*$dpi,3000*$dpi-$lift,$dt,0,0)
   $pointerError=[Math]::Max([Math]::Abs($moving.X-$resting.X-$dx),[Math]::Abs($moving.Y-$resting.Y-$dy))
   $maxError=[Math]::Max($maxError,$pointerError)
   if($pointerError-gt .001){throw 'Pickup spring delayed the pointer trajectory'}
   if($i-eq 1 -and ($resting.Y-ge 3000*$dpi -or $resting.Y-le 3000*$dpi-$lift)){throw 'Initial pickup lift jumped or disappeared'}
   $moving.Step($dt,$false,$true,$time/.5,.5,1);$resting.Step($dt,$false,$true,$time/.5,.5,1)
   $samples++
  }
  if([Math]::Abs($resting.Y-(3000*$dpi-$lift))-gt .01*$dpi){throw 'Pickup lift failed to settle'}
  $moving.MoveHeld(-10000,-10000,$dt,-10000,-10000)
  if($moving.X-lt $moving.FlightMargin -or $moving.Y-lt 16*$dpi){throw 'Direct tracking escaped the upper bounds'}
  $moving.MoveHeld(100000,100000,$dt,100000,100000)
  if($moving.X-gt $moving.Width-$moving.FlightMargin -or $moving.Y-gt $moving.Floor){throw 'Direct tracking escaped the lower bounds'}
 }
}
$result=@{passed=$true;samples=$samples;maxPointerErrorPixels=$maxError;pickupLiftPreserved=$true;boundsPreserved=$true}
if($ResultFile){[IO.File]::WriteAllText($ResultFile,($result|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
Write-Output ('PASS: '+$samples+' held tracking samples, no pointer spring lag, eased pickup and scene bounds preserved')
