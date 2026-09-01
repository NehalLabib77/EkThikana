$gradients = @{
    'tasks'    = @('FF5B3DF5','FF7C68FF')
    'ai'       = @('FF109238','FF22C55E')
    'study'    = @('FF6B46FF','FF8B5CF6')
    'commute'  = @('FF1B72CC','FF4FA3F0')
    'bazar'    = @('FFE0388A','FFF25BA7')
    'medicine' = @('FF16B8AD','FF22D3B7')
    'expense'  = @('FFFF8A1E','FFFFB55A')
}
function L($hex) {
    $r = [Convert]::ToInt32($hex.Substring(2,2),16) / 255.0
    $g = [Convert]::ToInt32($hex.Substring(4,2),16) / 255.0
    $b = [Convert]::ToInt32($hex.Substring(6,2),16) / 255.0
    function s($c){ if ($c -le 0.03928) { $c/12.92 } else { [Math]::Pow(($c+0.055)/1.055, 2.4) } }
    return 0.2126*(s $r) + 0.7152*(s $g) + 0.0722*(s $b)
}
function ratio($l1,$l2){ $a=[Math]::Max($l1,$l2); $b=[Math]::Min($l1,$l2); return ($a+0.05)/($b+0.05) }
$W = L 'FFFFFFFF'
Write-Host ("{0,-10} {1,7} {2,7}" -f 'Module','Hex','R:W')
foreach ($k in $gradients.Keys) {
    foreach ($hex in $gradients[$k]) {
        $r = ratio (L $hex) $W
        Write-Host ("{0,-10} {1,7} {2,7:F2}" -f $k,$hex,$r)
    }
}
