$gradients = @{
    'study'    = @('FF6B46FF','FF8457E9')
    'medicine' = @('FF147E6D','FF158472')
    'expense'  = @('FFB26015','FF996C36')
    'commute'  = @('FF1B72CC','FF3B7AB4')
    'bazar'    = @('FFE0388A','FFC14885')
    'tasks'    = @('FF5B3DF5','FF6F5DE5')
    'ai'       = @('FF0E8332','FF16803D')
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
Write-Host ("{0,-10} {1,-7} {2,7} {3,7}" -f 'Module','End','Hex','R:W')
foreach ($k in $gradients.Keys) {
    foreach ($hex in $gradients[$k]) {
        $r = ratio (L $hex) $W
        Write-Host ("{0,-10} {1,-7} {2,7} {3,7:F2}" -f $k,'',$hex,$r)
    }
}
