import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/widgets/group_circle_avatar.dart';
import 'package:musi_link/widgets/image_source_picker.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

InputDecoration _groupInputDecoration(
  ColorScheme colorScheme, {
  required String hint,
  required IconData icon,
  Widget? suffixIcon,
}) => InputDecoration(
  hintText: hint,
  prefixIcon: Icon(icon),
  suffixIcon: suffixIcon,
  filled: true,
  fillColor: colorScheme.surfaceContainerHighest,
  border: AppTheme.pillInputBorder,
  enabledBorder: AppTheme.pillInputBorder,
  focusedBorder: AppTheme.pillInputBorder,
  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
);

class CreateGroupChatScreen extends ConsumerStatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  ConsumerState<CreateGroupChatScreen> createState() =>
      _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends ConsumerState<CreateGroupChatScreen> {
  final _selected = <String>{};
  bool _openingName = false;

  Future<void> _continue(List<AppUser> selectedUsers) async {
    if (_openingName || selectedUsers.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() => _openingName = true);
    try {
      await context.push<void>(
        '/new-group-chat/name',
        extra: List<AppUser>.unmodifiable(selectedUsers),
      );
    } finally {
      if (mounted) setState(() => _openingName = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final friends = ref.watch(friendProfilesStreamProvider);
    ref.listen(friendProfilesStreamProvider, (_, next) {
      final users = next.asData?.value;
      if (users == null) return;
      final availableIds = users
          .where((user) => !user.isDeleted)
          .map((user) => user.uid)
          .toSet();
      if (_selected.any((uid) => !availableIds.contains(uid))) {
        setState(() => _selected.retainAll(availableIds));
      }
    });
    final selectedUsers =
        friends.asData?.value
            .where((user) => !user.isDeleted && _selected.contains(user.uid))
            .toList() ??
        <AppUser>[];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.groupChatNew)),
      floatingActionButton: selectedUsers.length >= 2
          ? FloatingActionButton(
              heroTag: 'group-chat-next',
              tooltip: l10n.onboardingNext,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              onPressed: _openingName ? null : () => _continue(selectedUsers),
              child: const Icon(LucideIcons.arrowRight),
            )
          : null,
      body: SafeArea(
        child: _FriendPicker(
          friends: friends,
          selected: _selected,
          maxSelected: ChatService.maxGroupParticipants - 1,
          memberCount: selectedUsers.isEmpty ? null : selectedUsers.length + 1,
          emptyMessage: l10n.groupChatNeedFriends,
          onChanged: (uid, selected) => setState(
            () => selected ? _selected.add(uid) : _selected.remove(uid),
          ),
        ),
      ),
    );
  }
}

/// Buscador y lista de amigos seleccionables, compartidos por la creación del
/// grupo y la incorporación de miembros.
class _FriendPicker extends StatefulWidget {
  const _FriendPicker({
    required this.friends,
    required this.selected,
    this.excluded = const {},
    required this.maxSelected,
    required this.memberCount,
    required this.emptyMessage,
    required this.onChanged,
  });

  final AsyncValue<List<AppUser>> friends;
  final Set<String> selected;

  /// Amigos que no se ofrecen, como quienes ya son miembros del grupo.
  final Set<String> excluded;
  final int maxSelected;

  /// Total de miembros que tendría el grupo; null oculta la etiqueta.
  final int? memberCount;
  final String emptyMessage;
  final void Function(String uid, bool selected) onChanged;

  @override
  State<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<_FriendPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final memberCount = widget.memberCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: _groupInputDecoration(
              colorScheme,
              hint: l10n.groupChatSearchFriends,
              icon: LucideIcons.search,
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .deleteButtonTooltip,
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (memberCount != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.groupChatMembers(memberCount),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        Expanded(
          child: widget.friends.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.socialErrorLoading)),
            data: (users) => _buildFriends(users, l10n),
          ),
        ),
      ],
    );
  }

  Widget _buildFriends(List<AppUser> users, AppLocalizations l10n) {
    final friends = users
        .where((user) => !user.isDeleted && !widget.excluded.contains(user.uid))
        .toList();
    if (friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(widget.emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }
    final query = _search.text.trim().toLowerCase();
    final usernameQuery = query.startsWith('@') ? query.substring(1) : query;
    final matches =
        friends
            .where(
              (user) =>
                  user.displayName.toLowerCase().contains(query) ||
                  user.username.toLowerCase().contains(usernameQuery),
            )
            .toList()
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    if (matches.isEmpty) return Center(child: Text(l10n.searchNoResults));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final user = matches[index];
        final selected = widget.selected.contains(user.uid);
        return CheckboxListTile(
          key: ValueKey(user.uid),
          value: selected,
          secondary: UserCircleAvatar(
            photoUrl: user.photoUrl,
            name: user.displayName,
            radius: 20,
          ),
          title: Text(user.displayName),
          subtitle: Text('@${user.username}'),
          onChanged: !selected && widget.selected.length >= widget.maxSelected
              ? null
              : (value) {
                  if (value == true) _search.clear();
                  widget.onChanged(user.uid, value == true);
                },
        );
      },
    );
  }
}

/// Añade a un grupo existente amigos de quien los elige.
class AddGroupMembersScreen extends ConsumerStatefulWidget {
  const AddGroupMembersScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<AddGroupMembersScreen> createState() =>
      _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends ConsumerState<AddGroupMembersScreen> {
  final _selected = <String>{};
  bool _saving = false;
  String? _error;

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/group-chat/${Uri.encodeComponent(widget.chatId)}');
    }
  }

  Future<void> _add(List<String> participantIds) async {
    if (_saving || participantIds.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(chatServiceProvider)
          .addGroupMembers(widget.chatId, participantIds);
      if (mounted) _close();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            error is FirebaseFunctionsException &&
                error.code == 'resource-exhausted'
            ? l10n.authErrorTooManyRequests
            : l10n.groupChatAddMembersError;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final chat = ref.watch(groupChatProvider(widget.chatId));
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final group = chat.hasError ? null : chat.value;
    final members = group != null && group.isGroup
        ? group.participants.toSet()
        : const <String>{};
    final friends = ref.watch(friendProfilesStreamProvider);
    // Quien deja de ser amigo o entra al grupo mientras tanto no se envía ni
    // ocupa una de las plazas libres.
    final selectedIds =
        friends.asData?.value
            .where(
              (user) =>
                  !user.isDeleted &&
                  !members.contains(user.uid) &&
                  _selected.contains(user.uid),
            )
            .map((user) => user.uid)
            .toList() ??
        const <String>[];

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.groupChatAddMembers)),
        floatingActionButton: selectedIds.isEmpty
            ? null
            : FloatingActionButton(
                heroTag: 'group-chat-add-members',
                tooltip: l10n.groupChatAddMembers,
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                onPressed: _saving ? null : () => _add(selectedIds),
                child: _saving
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(LucideIcons.check),
              ),
        body: SafeArea(
          child: !members.contains(uid)
              ? Center(
                  child: chat.isLoading
                      ? const CircularProgressIndicator()
                      : Text(l10n.groupChatUnavailable),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _FriendPicker(
                        friends: friends,
                        selected: selectedIds.toSet(),
                        excluded: members,
                        maxSelected:
                            ChatService.maxGroupParticipants - members.length,
                        memberCount: members.length + selectedIds.length,
                        emptyMessage: l10n.groupChatNoFriendsToAdd,
                        onChanged: (uid, selected) => setState(() {
                          _selected.retainAll(selectedIds);
                          selected ? _selected.add(uid) : _selected.remove(uid);
                        }),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 88, 16),
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class NameGroupChatScreen extends ConsumerStatefulWidget {
  const NameGroupChatScreen({super.key, required this.participants});
  final List<AppUser> participants;

  @override
  ConsumerState<NameGroupChatScreen> createState() =>
      _NameGroupChatScreenState();
}

class _NameGroupChatScreenState extends ConsumerState<NameGroupChatScreen> {
  final _name = TextEditingController();
  late final String _chatId = ref.read(chatServiceProvider).newGroupChatId();
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
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
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photo = image;
      _photoBytes = bytes;
    });
  }

  Future<void> _create() async {
    if (_saving || _name.text.trim().isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final chat = await ref
          .read(chatServiceProvider)
          .createGroupChat(
            chatId: _chatId,
            name: _name.text,
            participantIds: widget.participants
                .map((user) => user.uid)
                .toList(),
          );
      // Storage solo admite la foto de un grupo existente. Si falla, el grupo
      // ya está creado y la foto puede añadirse después desde sus datos.
      final photo = _photo;
      var photoFailed = false;
      if (photo != null) {
        try {
          await ref.read(groupPhotoUploaderProvider)(chat.id, photo);
        } catch (_) {
          photoFailed = true;
        }
      }
      if (!mounted) return;
      if (photoFailed) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.groupChatPhotoError)),
        );
      }
      context.go('/group-chat/${Uri.encodeComponent(chat.id)}', extra: chat);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is TimeoutException || isNetworkError(error)
            ? l10n.groupChatConnectionError
            : error is FirebaseFunctionsException &&
                  error.code == 'resource-exhausted'
            ? l10n.authErrorTooManyRequests
            : l10n.groupChatCreateError;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final currentUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final currentUser = ref.watch(currentUserProvider).asData?.value;
    final hasName = _name.text.trim().isNotEmpty;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.groupChatName)),
        floatingActionButton: FloatingActionButton(
          heroTag: 'group-chat-create',
          tooltip: l10n.groupChatCreate,
          backgroundColor: hasName
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          foregroundColor: hasName
              ? colorScheme.onPrimary
              : colorScheme.onSurface.withAlpha(AppTokens.alphaDisabled),
          onPressed: _saving || !hasName ? null : _create,
          child: _saving
              ? SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.onPrimary,
                  ),
                )
              : const Icon(LucideIcons.check),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 16),
                      child: Center(
                        child: GroupPhotoButton(
                          localBytes: _photoBytes,
                          tooltip: _photo == null
                              ? l10n.groupChatAddPhoto
                              : l10n.groupChatChangePhoto,
                          onTap: _saving ? null : _pickPhoto,
                        ),
                      ),
                    ),
                    TextField(
                      controller: _name,
                      autofocus: true,
                      enabled: !_saving,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      decoration: _groupInputDecoration(
                        colorScheme,
                        hint: l10n.groupChatName,
                        icon: LucideIcons.users,
                      ),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _create(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Text(
                        l10n.groupChatMembers(widget.participants.length + 1),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    if (currentUid != null)
                      ListTile(
                        key: ValueKey(currentUid),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: UserCircleAvatar(
                          photoUrl: currentUser?.photoUrl ?? '',
                          name: currentUser?.displayName ?? l10n.groupChatYou,
                          radius: 20,
                        ),
                        title: Text(l10n.groupChatYou),
                      ),
                    for (final user in widget.participants)
                      ListTile(
                        key: ValueKey(user.uid),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        leading: UserCircleAvatar(
                          photoUrl: user.photoUrl,
                          name: user.displayName,
                          radius: 20,
                        ),
                        title: Text(user.displayName),
                        subtitle: Text('@${user.username}'),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          _error!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
