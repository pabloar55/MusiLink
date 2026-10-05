import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/theme/app_theme.dart';

/// Desliza un mensaje hacia la derecha para responderlo.
///
/// Con [onReply] nulo el gesto queda desactivado sin alterar el árbol, de modo
/// que la burbuja conserva su estado al confirmarse un mensaje pendiente.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, this.onReply});

  final Widget child;
  final VoidCallback? onReply;

  /// Desplazamiento a partir del cual soltar el mensaje inicia la respuesta.
  static const double triggerOffset = 56;
  static const double _maxOffset = 76;
  static const double _iconExtent = 32;

  /// Franja del borde izquierdo reservada al gesto de volver atrás.
  static const double _backGestureWidth = 20;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _dragged = 0;
  bool _armed = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    _offset.stop();
    _dragged = _offset.value;
    _armed = false;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragged = math.max(0.0, _dragged + (details.primaryDelta ?? 0));
    // Pasado el umbral el mensaje ofrece resistencia en lugar de seguir al dedo.
    final offset = _dragged <= SwipeToReply.triggerOffset
        ? _dragged
        : SwipeToReply.triggerOffset +
              (_dragged - SwipeToReply.triggerOffset) * 0.3;
    _offset.value = math.min(offset, SwipeToReply._maxOffset);
    final armed = _dragged >= SwipeToReply.triggerOffset;
    if (armed && !_armed) HapticFeedback.selectionClick().ignore();
    _armed = armed;
  }

  void _onDragEnd([DragEndDetails? details]) {
    final reply = details != null && _armed;
    _armed = false;
    _dragged = 0;
    _offset.animateTo(
      0,
      duration: AppTokens.durationFast,
      curve: Curves.easeOut,
    );
    if (reply) widget.onReply?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onReply = widget.onReply;
    final colorScheme = Theme.of(context).colorScheme;
    final edgeInset =
        MediaQuery.paddingOf(context).left + SwipeToReply._backGestureWidth;

    return Semantics(
      customSemanticsActions: onReply == null
          ? null
          : {
              CustomSemanticsAction(
                label: AppLocalizations.of(context)!.chatReply,
              ): onReply,
            },
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: onReply == null
            ? const {}
            : {
                _ReplyDragRecognizer:
                    GestureRecognizerFactoryWithHandlers<_ReplyDragRecognizer>(
                      () => _ReplyDragRecognizer(debugOwner: this),
                      (recognizer) => recognizer
                        ..edgeInset = edgeInset
                        ..onStart = _onDragStart
                        ..onUpdate = _onDragUpdate
                        ..onEnd = _onDragEnd
                        ..onCancel = _onDragEnd,
                    ),
              },
        child: AnimatedBuilder(
          animation: _offset,
          child: widget.child,
          builder: (context, child) {
            final offset = _offset.value;
            final progress = math.min(1.0, offset / SwipeToReply.triggerOffset);
            final armed = offset >= SwipeToReply.triggerOffset;
            return Stack(
              fit: StackFit.passthrough,
              children: [
                Transform.translate(offset: Offset(offset, 0), child: child),
                if (offset > 0)
                  Positioned(
                    left: math.max(
                      0.0,
                      (offset - SwipeToReply._iconExtent) / 2,
                    ),
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: progress,
                          child: Transform.scale(
                            scale: 0.6 + 0.4 * progress,
                            child: Container(
                              width: SwipeToReply._iconExtent,
                              height: SwipeToReply._iconExtent,
                              decoration: BoxDecoration(
                                color: armed
                                    ? colorScheme.primary
                                    : colorScheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.reply,
                                size: 18,
                                color: armed
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// No compite por los toques que empiezan en el borde izquierdo, donde iOS
/// reconoce el gesto de volver a la pantalla anterior.
class _ReplyDragRecognizer extends HorizontalDragGestureRecognizer {
  _ReplyDragRecognizer({super.debugOwner});

  double edgeInset = 0;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event.position.dx >= edgeInset && super.isPointerAllowed(event);
}
