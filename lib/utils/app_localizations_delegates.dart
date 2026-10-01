import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';

/// Delegates de localización de la app junto con los de `material_ui` y
/// `cupertino_ui`.
///
/// `AppLocalizations.localizationsDelegates` (generado) registra los delegates
/// de `flutter_localizations`, que no resuelven los textos de los widgets de
/// `material_ui`.
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];
