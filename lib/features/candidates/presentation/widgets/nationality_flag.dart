import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/candidate_repository.dart';

/// Bundled flag image for an ISO country code, e.g. `KE` → `assets/flags/ke.png`.
String flagAsset(String code) => 'assets/flags/${code.toLowerCase()}.png';

/// The small flag of a maid nationality, e.g. next to "Kenya". Shows the
/// globe icon when the nationality or its flag is not known.
class NationalityFlag extends ConsumerWidget {
  const NationalityFlag({super.key, required this.nationality, this.height = 14});

  /// The nationality's name, as stored on the maid ("Kenya").
  final String nationality;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? code;
    for (final item
        in ref.watch(maidNationalitiesProvider).value ?? const []) {
      if (item.name == nationality) code = item.code;
    }
    return FlagImage(code: code, height: height);
  }
}

/// A flag by ISO country code (or the globe icon when [code] is null or its
/// flag is missing). Decorative: the nationality is written next to it.
class FlagImage extends StatelessWidget {
  const FlagImage({super.key, required this.code, this.height = 14});

  final String? code;
  final double height;

  @override
  Widget build(BuildContext context) {
    final globe = Icon(
      Icons.public_rounded,
      size: height + 2,
      color: AppColors.textSecondary,
    );
    final flag = code;
    if (flag == null) return globe;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: DecoratedBox(
        // A hairline keeps white flag edges visible on white cards.
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Image.asset(
          flagAsset(flag),
          height: height,
          width: height * 1.5,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => globe,
        ),
      ),
    );
  }
}
