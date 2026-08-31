function L($r,$g,$b) {
    $r2 = $r / 255.0; $g2 = $g / 255.0; $b2 = $b / 255.0
    function s($c){ if ($c -le 0.03928) { $c/12.92 } else { [Math]::Pow(($c+0.055)/1.055, 2.4) } }
    return 0.2126*(s $r2) + 0.7152*(s $g2) + 0.0722*(s $b2)
}
function ratio($l1,$l2){ $a=[Math]::Max($l1,$l2); $b=[Math]::Min($l1,$l2); return ($a+0.05)/($b+0.05) }
$W = L 255 255 255
# Iterate darker variants of each problem color and report the smallest darkening that crosses 4.5:1
$targets = @(
    @{ name='study';    rgb=@(139, 92, 246) },
    @{ name='medicine'; rgb=@(34, 211, 183) },
    @{ name='expense';  rgb=@(255, 181, 90) },
    @{ name='commute';  rgb=@(79, 163, 240) },
    @{ name='bazar';    rgb=@(242, 91, 167) },
    @{ name='tasks';    rgb=@(124, 104, 255) },
    @{ name='ai';       rgb=@(34, 197, 94)  }
)
foreach ($t in $targets) {
    $r,$g,$b = $t.rgb
    $cur = ratio (L $r $g $b) $W
    Write-Host ("{0,-10} original #{1:X2}{2:X2}{3:X2} ratio={4:F2}" -f $t.name, $r, $g, $b, $cur)
    # Try darkening factors
    foreach ($f in 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6) {
        $rn = [int]([Math]::Floor($r * $f))
        $gn = [int]([Math]::Floor($g * $f))
        $bn = [int]([Math]::Floor($b * $f))
        $rr = ratio (L $rn $gn $bn) $W
        if ($rr -ge 4.5) {
            Write-Host ("  factor={0:F2} -> #{1:X2}{2:X2}{3:X2} ratio={4:F2} <-- passes" -f $f, $rn, $gn, $bn, $rr)
            break
        } else {
            Write-Host ("  factor={0:F2} -> #{1:X2}{2:X2}{3:X2} ratio={4:F2}" -f $f, $rn, $gn, $bn, $rr)
        }
    }
}