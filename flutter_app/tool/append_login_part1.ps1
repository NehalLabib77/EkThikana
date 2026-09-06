# Append _LoginHero class to login_screen.dart.
$bnPath = Join-Path $PSScriptRoot 'login_helpers_bn.txt'
$bnRaw = [System.IO.File]::ReadAllText($bnPath, [System.Text.UTF8Encoding]::new($false))
# Strip any trailing line ending the file may carry.
$bnTagline = ($bnRaw -replace "`r?`n$", '').TrimEnd("`r", "`n")

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
              '__BN_TAGLINE_SLOT__',
            ),
            style: type.bodySecondary.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
'@

$append = $append.Replace('__BN_TAGLINE_SLOT__', $bnTagline)

$path = (Resolve-Path (Join-Path $PSScriptRoot '..\lib\features\auth\presentation\login_screen.dart')).Path
$append = $append -replace "`r?`n", "`r`n"
[System.IO.File]::AppendAllText(
    $path,
    $append,
    [System.Text.UTF8Encoding]::new($false)
)
Write-Host ("appended _LoginHero: " + $append.Length + " bytes")
