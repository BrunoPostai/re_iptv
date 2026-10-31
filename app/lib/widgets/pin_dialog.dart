import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Optional 4-6 digit parental PIN prompt.
///
/// Returns `true` when the entered code matches [expected] (or when [expected]
/// is empty, i.e. no PIN configured).
Future<bool> requestPin(
  BuildContext context, {
  required String expected,
  String title = 'Enter PIN',
}) async {
  if (expected.isEmpty) return true;

  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 260,
        child: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, letterSpacing: 8),
          onSubmitted: (value) => Navigator.of(context).pop(value == expected),
          decoration: const InputDecoration(counterText: '', hintText: '••••'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(controller.text == expected),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.of(context).accent,
            elevation: 0,
          ),
          child: const Text('Unlock'),
        ),
      ],
    ),
  );
  return result ?? false;
}
