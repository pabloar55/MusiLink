import 'package:material_ui/material_ui.dart';
import 'package:musi_link/theme/app_theme.dart';

/// Botón de filtro toggle semántico para selección exclusiva (tipo radio).
///
/// Diferencia con el patrón anterior: ya NO usa `onPressed: null` para simular
/// el estado "activo" — eso marcaba el botón como *disabled* para lectores de
/// pantalla. Ahora usa `Semantics` con `selected: true` y estilos explícitos.
class FilterButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onPressed;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;

  const FilterButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.fontSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveFontSize = fontSize ?? 13.0;
    final effectivePadding = padding ??
        const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceLG,
          vertical: AppTokens.spaceSM,
        );

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: AnimatedContainer(
        duration: AppTokens.durationFast,
        constraints: const BoxConstraints(minHeight: AppTokens.minTouchTarget),
        child: Material(
          color: isSelected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTokens.radiusFull),
          child: InkWell(
            onTap: isSelected ? null : onPressed,
            borderRadius: BorderRadius.circular(AppTokens.radiusFull),
            child: Padding(
              padding: effectivePadding,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: effectiveFontSize,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? cs.onPrimary : cs.onSurface,
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
