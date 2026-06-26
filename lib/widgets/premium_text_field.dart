import 'package:flutter/material.dart';

import 'fast_text_field.dart';

class PremiumTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final IconData prefixIcon;
  final bool obscureText;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int maxLines;

  const PremiumTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.prefixIcon,
    this.obscureText = false,
    required this.controller,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isMultiline = maxLines != 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        FastTextField(
          controller: controller,
          obscureText: obscureText,
          kind: isMultiline
              ? FastTextFieldKind.prose
              : (keyboardType == TextInputType.emailAddress
                  ? FastTextFieldKind.email
                  : FastTextFieldKind.standard),
          minLines: isMultiline ? 1 : null,
          maxLines: maxLines,
          textInputAction: textInputAction ??
              (isMultiline ? TextInputAction.newline : TextInputAction.next),
          onSubmitted: isMultiline
              ? null
              : (_) => FocusScope.of(context).nextFocus(),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(prefixIcon, size: 22),
          ),
        ),
      ],
    );
  }
}