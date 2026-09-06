# Append the private helper widget classes for the polish pass to
# login_screen.dart. UTF-8 without BOM, CRLF line endings.

$append = @'

/// Brand plate at the top of the sign-in form: logo in a soft rounded
/// square, the product name, and a tagline. Kept as its own widget so
/// the build method stays readable and so this header can be reused by
/// any "first-run" or "logged-out" experience that shows the same
/// hero block.
class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.colors, required this.type});

  final GochanoColorsExtension colors;
  final GochanoTypographyExtension type;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.lg,
        vertical: GochanoSpacing.xl,
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              borderRadius: GochanoRadius.lgAll,
              border: Border.all(color: colors.border),
            ),
            alignment: Alignment.center,
            child: Image.asset(
              LoginScreen._kBrandAsset,
              width: 48,
              height: 48,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.apps_rounded,
                size: 36,
                color: colors.brand,
              ),
            ),
          ),
          const SizedBox(height: GochanoSpacing.md),
          Text(
            'Gochano',
            style: type.pageTitle.copyWith(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            GochanoLanguage.text(
              'One place for everything',
              '__BN_TAGLINE__',
            ),
            style: type.bodySecondary.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

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

$path = (Resolve-Path 'lib/features/auth/presentation/login_screen.dart').Path
# Normalise line endings to CRLF to match the rest of the file.
$append = $append -replace "`r?`n", "`r`n"
[System.IO.File]::AppendAllText(
    $path,
    $append,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host ("appended " + $append.Length + " bytes")
Write-Host ("file is now " + ([System.IO.File]::ReadAllBytes($path).Length) + " bytes")
