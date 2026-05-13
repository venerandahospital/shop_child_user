import 'package:flutter/services.dart';

/// Forces input to lowercase so the email field always stays in small letters.
class LowercaseTextInputFormatter extends TextInputFormatter {
  const LowercaseTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toLowerCase(),
      composing: TextRange.empty,
    );
  }
}

/// Lowercase-only local part and domain; typical email shape.
final RegExp childEmailFormatRegex = RegExp(
  r'^[a-z0-9][a-z0-9._%+-]*@[a-z0-9][a-z0-9.-]*\.[a-z]{2,}$',
);

String? validateChildEmail(String? value) {
  final v = (value ?? '').trim().toLowerCase();
  if (v.isEmpty) return 'Please enter your email';
  if (!childEmailFormatRegex.hasMatch(v)) {
    return 'Enter a valid email using lowercase letters (e.g. name@example.com)';
  }
  return null;
}
