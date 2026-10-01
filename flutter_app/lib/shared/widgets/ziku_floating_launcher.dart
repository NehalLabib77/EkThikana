import 'package:flutter/material.dart';
import '../../core/design_system/gochano_colors.dart';

class ZikuFloatingLauncher extends StatelessWidget {
  const ZikuFloatingLauncher({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      label: 'Ziku AI Assistant',
      button: true,
      child: Tooltip(
        message: 'Ask Ziku AI',
        child: SizedBox(
          width: 54,
          height: 54,
          child: Material(
            key: const ValueKey('ziku_floating_launcher'),
            color: colors.surface,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.brand.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: ClipOval(
                  child: Image.asset(
                    'assets/Ziku.png',
                    semanticLabel: 'Ziku AI assistant avatar',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.brand,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
