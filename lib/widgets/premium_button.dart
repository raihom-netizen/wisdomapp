import 'package:flutter/material.dart';

class PremiumPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const PremiumPrimaryButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Visual Premium
        elevation: 2,
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
    );
  }
}