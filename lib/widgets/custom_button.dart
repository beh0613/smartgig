import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final bool filled;

  const CustomButton({
    super.key,
    required this.text,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: filled
            ? Theme.of(context).primaryColor
            : Colors.transparent,
        elevation: filled ? 2 : 0,
      ),
      child: Text(text, style: const TextStyle(fontSize: 16)),
    );
  }
}
