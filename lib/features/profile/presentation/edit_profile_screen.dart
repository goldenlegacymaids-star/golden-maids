import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/auth_scaffold.dart';
import '../data/profile_repository.dart';

/// Edit the signed-in user's name. Phone and email are changed through
/// verified flows (later), not edited directly.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text:
        ref.read(myProfileProvider).value?.fullName ??
        ref.read(authRepositoryProvider).currentUser?.fullName ??
        '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateFullName(_name.text.trim());
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      showAppSnackBar(context, 'Your profile has been updated.');
      context.pop();
    } on AppFailure catch (failure) {
      if (mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Edit profile',
      subtitle: 'This is the name we use on your requests and contracts.',
      children: [
        Form(
          key: _formKey,
          child: AppTextField(
            controller: _name,
            label: 'Full name',
            prefixIcon: Icons.person_outline_rounded,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.name],
            validator: Validators.fullName,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(label: 'Save changes', onPressed: _save),
      ],
    );
  }
}
