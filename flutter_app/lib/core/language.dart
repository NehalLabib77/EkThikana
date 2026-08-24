import 'package:flutter/material.dart';
import 'theme.dart';

class EkLanguage {
  EkLanguage._();

  /// false = English, true = Bangla. The toggle intentionally shows one
  /// language at a time instead of placing English and Bangla side-by-side.
  static final ValueNotifier<bool> bangla = ValueNotifier<bool>(false);

  static String text(String en, String bn) => bangla.value ? bn : en;
}

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, isBn, _) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1F7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _choice('EN', !isBn, () => EkLanguage.bangla.value = false),
              _choice('বাংলা', isBn, () => EkLanguage.bangla.value = true),
            ],
          ),
        );
      },
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x12000000), blurRadius: 5)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? EkColors.purple : EkColors.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class LocalizedText extends StatelessWidget {
  const LocalizedText(
    this.en,
    this.bn, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String en;
  final String bn;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (_, isBn, __) => Text(
        isBn ? bn : en,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      ),
    );
  }
}
