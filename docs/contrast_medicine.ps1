function L($r,$g,$b) {
    $r2 = $r / 255.0; $g2 = $g / 255.0; $b2 = $b / 255.0
    function s($c){ if ($c -le 0.03928) { $c/12.92 } else { [Math]::Pow(($c+0.055)/1.055, 2.4) } }
    return 0.2126*(s $r2) + 0.7152*(s $g2) + 0.0722*(s $b2)
}
function ratio($l1,$l2){ $a=[Math]::Max($l1,$l2); $b=[Math]::Min($l1,$l2); return ($a+0.05)/($b+0.05) }
$W = L 255 255 255
Write-Host "---bazar left end: search darker from E0388A (4.12:1)"
$target = @(224, 56, 138)
foreach ($f in 0.9, 0.85, 0.8, 0.75, 0.7) {
    $rn = [int]([Math]::Floor($target[0] * $f))
    $gn = [int]([Math]::Floor($target[1] * $f))
    $bn = [int]([Math]::Floor($target[2] * $f))
    $rr = ratio (L $rn $gn $bn) $W
    Write-Host ("factor={0:F2} #{1:X2}{2:X2}{3:X2} ratio={4:F2}" -f $f, $rn, $gn, $bn, $rr)
}