import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

class GoogleSignInWebButton extends StatelessWidget {
  const GoogleSignInWebButton({super.key});

  // Google Identity Services renders its largest button at 40px high.
  static const _buttonHeight = 40.0;
  static const _googleMaxWidth = 400.0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        // GIS only supports widths up to 400px. The auth form uses the same
        // maximum width, so this fills the whole button slot responsively.
        final buttonWidth = constraints.maxWidth.clamp(1.0, _googleMaxWidth);

        return SizedBox(
          width: buttonWidth,
          height: _buttonHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_buttonHeight / 2),
            child: KeyedSubtree(
              key: ValueKey(isDarkMode),
              child: web.renderButton(
                configuration: web.GSIButtonConfiguration(
                  type: web.GSIButtonType.standard,
                  theme: isDarkMode
                      ? web.GSIButtonTheme.filledBlack
                      : web.GSIButtonTheme.outline,
                  size: web.GSIButtonSize.large,
                  text: web.GSIButtonText.continueWith,
                  shape: web.GSIButtonShape.pill,
                  logoAlignment: web.GSIButtonLogoAlignment.left,
                  minimumWidth: buttonWidth,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
