import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';

enum AuthMethod {
  whatsapp('WhatsApp', Icons.chat_bubble_outline_rounded),
  email('Email', Icons.mail_outline_rounded);

  const AuthMethod(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Two-option pill switch: WhatsApp | Email.
class AuthMethodSwitch extends StatelessWidget {
  const AuthMethodSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AuthMethod value;
  final ValueChanged<AuthMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        children: [
          for (final method in AuthMethod.values)
            Expanded(
              child: _Segment(
                method: method,
                selected: method == value,
                onTap: () => onChanged(method),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final AuthMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textSecondary;

    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? AppColors.white : Colors.transparent,
          borderRadius: AppRadius.pillAll,
          boxShadow: selected ? AppShadows.soft : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(method.icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(
                  method.label,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
