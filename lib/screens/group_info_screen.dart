import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/utils/user_future_cache.dart';
import 'package:musi_link/widgets/adaptive_confirmation_dialog.dart';
import 'package:musi_link/widgets/group_circle_avatar.dart';
import 'package:musi_link/widgets/image_source_picker.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

/// Datos del grupo: foto editable por cualquier miembro, miembros y salida.
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen>
    with UserFutureCache {
  @override
  UserService get userService => ref.read(userServiceProvider);

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
      await ref.read(groupPhotoUploaderProvider)(widget.chatId, image);
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

  /// Vuelve a la lista sin esperar al backend: al confirmarse la salida, el
  /// grupo deja de ser legible y ni esta pantalla ni el chat podrían mostrarlo.
  Future<void> _leaveGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAdaptiveConfirmationDialog(
      context: context,
      title: l10n.groupChatLeaveTitle,
      content: l10n.groupChatLeaveBody,
      cancelLabel: l10n.chatDeleteCancel,
      confirmLabel: l10n.groupChatLeave,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(chatServiceProvider);
    final router = GoRouter.of(context);
    // Cierra esta pantalla y el chat que queda debajo.
    if (router.canPop()) router.pop();
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/?tab=messages');
    }
    try {
      await service.leaveGroupChat(widget.chatId);
    } catch (_) {
      if (!messenger.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.groupChatLeaveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chat = ref.watch(groupChatProvider(widget.chatId));
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    // Un grupo ausente o un error de permisos nunca muestran datos anteriores.
    final current = chat.hasError ? null : chat.value;
    final group =
        current != null && current.isGroup && current.participants.contains(uid)
        ? current
        : null;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: group == null
            ? Center(
                child: chat.isLoading
                    ? const CircularProgressIndicator()
                    : Text(l10n.groupChatUnavailable),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 16),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        Text(
                          group.name,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.groupChatMembers(group.participants.length),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (group.participants.length <
                      ChatService.maxGroupParticipants)
                    ListTile(
                      leading: const CircleAvatar(
                        radius: 20,
                        child: Icon(LucideIcons.userPlus, size: 20),
                      ),
                      title: Text(l10n.groupChatAddMembers),
                      onTap: () => context.push(
                        '/group-chat/${Uri.encodeComponent(widget.chatId)}/add-members',
                      ),
                    ),
                  for (final memberId in group.participants)
                    FutureBuilder<AppUser?>(
                      key: ValueKey(memberId),
                      future: getUserFuture(memberId),
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
                              : () => context.push(
                                  userProfileLocation(user.uid),
                                  extra: user,
                                ),
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
                    onTap: _leaveGroup,
                  ),
                ],
              ),
      ),
    );
  }
}
