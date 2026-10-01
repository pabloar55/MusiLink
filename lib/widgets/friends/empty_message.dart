import 'package:material_ui/material_ui.dart';

class EmptyMessage extends StatelessWidget {
  final String text;
  const EmptyMessage({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
          fontSize: 14,
        ),
      ),
    );
  }
}
