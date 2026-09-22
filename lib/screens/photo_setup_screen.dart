import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/profile_photo_upload_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/widgets/image_source_picker.dart';

class PhotoSetupScreen extends ConsumerStatefulWidget {
  const PhotoSetupScreen({super.key});

  @override
  ConsumerState<PhotoSetupScreen> createState() => _PhotoSetupScreenState();
}

class _PhotoSetupScreenState extends ConsumerState<PhotoSetupScreen> {
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  bool _isContinuing = false;

  Future<void> _pickImage() async {
    final source = await showImageSourcePicker(context);
    if (source == null || !mounted) return;

    final image = await ref
        .read(imagePickerProvider)
        .pickImage(
          source: source,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85,
        );

    if (image != null) {
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });
    }
  }

  void _handleContinue() {
    if (_isContinuing) return;
    final image = _selectedImage;
    if (image != null) {
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid == null) return;
      final messenger = ScaffoldMessenger.of(context);
      final errorMessage = AppLocalizations.of(context)!.photoSetupError;
      unawaited(
        ref
            .read(profilePhotoUploadProvider.notifier)
            .upload(
              uid: uid,
              image: image,
              bytes: _selectedImageBytes!,
              isSetup: true,
            )
            .catchError((Object error) {
              if (!messenger.mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(errorMessage),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }),
      );
    }
    setState(() => _isContinuing = true);
    ref.read(appRouterNotifierProvider).setPhotoSetupDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final hasPhoto = _selectedImage != null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // Avatar
              GestureDetector(
                onTap: _isContinuing ? null : _pickImage,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.surfaceContainerHighest,
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: ClipOval(
                        child: hasPhoto
                            ? Image.memory(
                                _selectedImageBytes!,
                                fit: BoxFit.cover,
                              )
                            : Icon(
                                LucideIcons.user,
                                size: 52,
                                color: colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        LucideIcons.camera,
                        size: 14,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                l10n.photoSetupTitle,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                l10n.photoSetupSubtitle,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),

              const Spacer(flex: 2),

              // Primary button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _isContinuing
                      ? null
                      : (hasPhoto ? _handleContinue : _pickImage),
                  child: Text(
                    hasPhoto ? l10n.photoSetupContinue : l10n.photoSetupChoose,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Skip / change photo link
              TextButton(
                onPressed: _isContinuing
                    ? null
                    : (hasPhoto ? _pickImage : _handleContinue),
                child: Text(
                  hasPhoto ? l10n.photoSetupChange : l10n.photoSetupSkip,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
