# Append _CarrierSupportStrip class to login_screen.dart.

$append = @'

/// Compact strip showing which carriers Gochano currently supports.
/// Two equal-width badges so the supported prefixes are visible at a
/// glance, even before the user starts typing.
class _CarrierSupportStrip extends StatelessWidget {
  const _CarrierSupportStrip({required this.colors, required this.type});

  final GochanoColorsExtension colors;
  final GochanoTypographyExtension type;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GochanoBadge(
            label: GochanoLanguage.text(
              'Robi · 018',
              'Robi · 018',
            ),
            tone: GochanoBadgeTone.brand,
            icon: Icons.sim_card_outlined,
          ),
        ),
        const SizedBox(width: GochanoSpacing.sm),
        Expanded(
          child: GochanoBadge(
            label: GochanoLanguage.text(
              'Cirkle · 016',
              'Cirkle · 016',
            ),
            tone: GochanoBadgeTone.info,
            icon: Icons.sim_card_outlined,
          ),
        ),
      ],
    );
  }
}
'@

$path = (Resolve-Path (Join-Path $PSScriptRoot '..\lib\features\auth\presentation\login_screen.dart')).Path
$append = $append -replace "`r?`n", "`r`n"
[System.IO.File]::AppendAllText(
    $path,
    $append,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host ("appended _CarrierSupportStrip: " + $append.Length + " bytes")
