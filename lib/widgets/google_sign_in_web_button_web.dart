import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

class GoogleSignInWebButton extends StatelessWidget {
  const GoogleSignInWebButton({super.key});

  static const _buttonWidth = 320.0;
  static const _buttonHeight = 40.0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SizedBox(
        width: _buttonWidth,
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
                minimumWidth: _buttonWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
