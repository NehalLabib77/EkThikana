$pairs = @(
    @{ name='study';    before='6B46FF,8B5CF6'; after='6B46FF,8457E9' },
    @{ name='medicine'; before='16B8AD,22D3B7'; after='147E6D,158472' },
    @{ name='expense';  before='FF8A1E,FFB55A'; after='B26015,996C36' },
    @{ name='commute';  before='1B72CC,4FA3F0'; after='1B72CC,3B7AB4' },
    @{ name='bazar';    before='E0388A,F25BA7'; after='C9327C,C14885' },
    @{ name='tasks';    before='5B3DF5,7C68FF'; after='5B3DF5,6F5DE5' },
    @{ name='ai';       before='109238,22C55E'; after='0E8332,16803D' }
)
function ParseHue($hex) {
    $r = [Convert]::ToInt32($hex.Substring(0,2),16) / 255.0
    $g = [Convert]::ToInt32($hex.Substring(2,2),16) / 255.0
    $b = [Convert]::ToInt32($hex.Substring(4,2),16) / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $d = $max - $min
    if ($d -eq 0) { return 0 }
    if ($max -eq $r) { return (60 * ((($g - $b) / $d) % 6)) }
    if ($max -eq $g) { return (60 * ((($b - $r) / $d) + 2)) }
    return (60 * ((($r - $g) / $d) + 4))
}
function Sat($hex) {
    $r = [Convert]::ToInt32($hex.Substring(0,2),16) / 255.0
    $g = [Convert]::ToInt32($hex.Substring(2,2),16) / 255.0
    $b = [Convert]::ToInt32($hex.Substring(4,2),16) / 255.0
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    if ($max -eq 0) { return 0 }
    return ($max - $min) / $max
}
function L($hex) {
    $r = [Convert]::ToInt32($hex.Substring(0,2),16) / 255.0
    $g = [Convert]::ToInt32($hex.Substring(2,2),16) / 255.0
    $b = [Convert]::ToInt32($hex.Substring(4,2),16) / 255.0
    function s($c){ if ($c -le 0.03928) { $c/12.92 } else { [Math]::Pow(($c+0.055)/1.055, 2.4) } }
    return 0.2126*(s $r) + 0.7152*(s $g) + 0.0722*(s $b)
}
Write-Host ("{0,-10} {1,9} {2,9} {3,9} {4,9}" -f 'Module','OldHue','NewHue','LumOld','LumNew')
foreach ($p in $pairs) {
    $b = $p.before -split ','
    $a = $p.after -split ','
    Write-Host ("{0,-10} {1,9:F1} {2,9:F1} {3,9:F3} {4,9:F3}" -f $p.name, (ParseHue $b[1]), (ParseHue $a[1]), (L $b[1]), (L $a[1]))
}