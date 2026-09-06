"""Fix the type class names in login_screen.dart.

`GochanoColorsExtension` and `GochanoTypographyExtension` are placeholders
I used while writing the helper widget classes. The real extension classes
are `GochanoColorsX` and `GochanoTypographyX` (the `X` suffix is the
Dart convention for an extension on BuildContext). This script does a
literal, byte-exact replacement of those two identifiers.
"""

from pathlib import Path

PATH = Path("lib/features/auth/presentation/login_screen.dart")

text = PATH.read_bytes().decode("utf-8")
text = text.replace("GochanoColorsX", "GochanoColors")
text = text.replace("GochanoTypographyX", "GochanoTypography")
PATH.write_bytes(text.encode("utf-8"))
print("renamed extension classes")
