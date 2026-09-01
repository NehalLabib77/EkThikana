$gradients = @{
    'study'    = @('FF6B46FF','FF8B5CF6','FF2A1F66','FF3F2EAA')
    'medicine' = @('FF16B8AD','FF22D3B7','FF0D6B63','FF138C82')
    'expense'  = @('FFFF8A1E','FFFFB55A','FF8A4A0E','FFB8641D')
    'commute'  = @('FF1B72CC','FF4FA3F0','FF103E80','FF1F60B5')
    'bazar'    = @('FFE0388A','FFF25BA7','FF7C1F4E','FFA8326B')
    'tasks'    = @('FF5B3DF5','FF7C68FF','FF2C1D8C','FF4535B5')
    'ai'       = @('FF109238','FF22C55E','FF0D5C1E','FF158438')
    'greeting' = @('FF4F2DE8','FF7A55FF','FF14B8A6')
    'splash'   = @('FF4F2DE8','FF7A55FF','FF0A0033')
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
$B = L 'FF000000'
Write-Host ("{0,-10} {1,-7} {2,7} {3,7} {4,7} {5,7}" -f 'Module','End','L->W','L->B','D->W','D->B')
foreach ($k in $gradients.Keys) {
    $g = $gradients[$k]
    $n = $g.Count
    $pairs = if ($n -eq 2) { 2 } elseif ($n -eq 3) { 3 } else { 2 }
    if ($n -eq 2) {
        $lHex = $g[0]; $dHex = $g[0]
        $lL = L $lHex
        $dL = L $dHex
        Write-Host ("{0,-10} {1,-7} {2,7:F2} {3,7:F2} {4,7:F2} {5,7:F2}" -f $k,'left',(ratio $lL $W),(ratio $lL $B),(ratio $dL $W),(ratio $dL $B))
    } elseif ($n -eq 3) {
        for ($i = 0; $i -lt 3; $i++) {
            $lHex = $g[$i]
            $lL = L $lHex
            Write-Host ("{0,-10} {1,-7} {2,7:F2} {3,7:F2} {4,7:F2} {5,7:F2}" -f $k,"stop$($i+1)",(ratio $lL $W),(ratio $lL $B),(ratio $lL $W),(ratio $lL $B))
        }
    } else {
        for ($i = 0; $i -lt 2; $i++) {
            $lHex = $g[$i]; $dHex = $g[$i + 2]
            $lL = L $lHex; $dL = L $dHex
            $end = if ($i -eq 0) {'left'} else {'right'}
            Write-Host ("{0,-10} {1,-7} {2,7:F2} {3,7:F2} {4,7:F2} {5,7:F2}" -f $k,$end,(ratio $lL $W),(ratio $lL $B),(ratio $dL $W),(ratio $dL $B))
        }
    }
}
