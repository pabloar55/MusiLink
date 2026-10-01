import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/widgets/group_circle_avatar.dart';
import 'package:musi_link/widgets/image_source_picker.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

/// Datos del grupo: foto editable por cualquier miembro, miembros y salida.
class GroupInfoSheet extends ConsumerStatefulWidget {
  const GroupInfoSheet({
    super.key,
    required this.group,
    required this.getUser,
    required this.onOpenProfile,
    required this.onLeave,
  });

  final Chat group;
  final Future<AppUser?> Function(String uid) getUser;
  final void Function(AppUser user) onOpenProfile;
  final VoidCallback onLeave;

  @override
  ConsumerState<GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends ConsumerState<GroupInfoSheet> {
  Uint8List? _photoBytes;
  bool _isUploadingPhoto = false;
  bool _photoFailed = false;

  Future<void> _changePhoto() async {
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
    if (image == null || !mounted) return;

    final previous = _photoBytes;
    try {
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _isUploadingPhoto = true;
        _photoFailed = false;
      });
      await ref.read(groupPhotoUploaderProvider)(widget.group.id, image);
      if (mounted) setState(() => _isUploadingPhoto = false);
    } catch (_) {
      // Los servicios ya han registrado el error.
      if (!mounted) return;
      setState(() {
        _photoBytes = previous;
        _isUploadingPhoto = false;
        _photoFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // La hoja sigue los cambios del grupo mientras permanece abierta.
    final group =
        ref.watch(groupChatProvider(widget.group.id)).value ?? widget.group;

    return ListView(
      shrinkWrap: true,
      children: [
        const SizedBox(height: 8),
        Center(
          child: GroupPhotoButton(
            photoUrl: group.photoUrl,
            localBytes: _photoBytes,
            tooltip: l10n.groupChatChangePhoto,
            isUploading: _isUploadingPhoto,
            onTap: _changePhoto,
          ),
        ),
        if (_photoFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              l10n.groupChatPhotoError,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
        ListTile(
          title: Text(group.name, textAlign: TextAlign.center),
          subtitle: Text(
            l10n.groupChatMembers(group.participants.length),
            textAlign: TextAlign.center,
          ),
        ),
        for (final uid in group.participants)
          FutureBuilder<AppUser?>(
            future: widget.getUser(uid),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return ListTile(
                leading: UserCircleAvatar(
                  photoUrl: user?.photoUrl ?? '',
                  name: user?.displayName ?? '',
                  radius: 20,
                ),
                title: Text(user?.displayName ?? l10n.socialUser),
                onTap: user == null || user.isDeleted
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        widget.onOpenProfile(user);
                      },
              );
            },
          ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(LucideIcons.logOut, color: colorScheme.error),
          title: Text(
            l10n.groupChatLeave,
            style: TextStyle(color: colorScheme.error),
          ),
          onTap: () {
            Navigator.of(context).pop();
            widget.onLeave();
          },
        ),
      ],
    );
  }
}
