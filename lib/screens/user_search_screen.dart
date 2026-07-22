import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/theme/app_theme.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:go_router/go_router.dart';

/// Pantalla para buscar usuarios y enviar solicitudes de amistad.
class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AppUser> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  // Cache de relaciones para los resultados actuales
  final Map<String, RelationshipResult> _relationships = {};
  bool _hasError = false;

  /// UID of the authenticated user from the Riverpod provider.
  /// If empty (session lost), searchUsers will return no results safely.
  String get _currentUid =>
      ref.read(firebaseAuthProvider).currentUser?.uid ?? '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _isLoading = false;
        _hasError = false;
        _relationships.clear();
      });
      return;
    }
    setState(() => _isLoading = true);
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _hasError = false;
    });

    try {
      final users = await ref
          .read(userServiceProvider)
          .searchUsers(query, excludeUid: _currentUid);

      // Cargar relaciones para todos los resultados
      final relationships = <String, RelationshipResult>{};
      for (final user in users) {
        relationships[user.uid] = await ref
            .read(friendServiceProvider)
            .getRelationship(user.uid);
      }

      if (mounted) {
        setState(() {
          _results = users;
          _relationships
            ..clear()
            ..addAll(relationships);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _sendRequest(String uid) async {
    try {
      await ref.read(friendServiceProvider).sendRequest(uid);
      if (!mounted) return;
      // Refrescar solo este usuario
      final rel = await ref.read(friendServiceProvider).getRelationship(uid);
      if (mounted) {
        setState(() => _relationships[uid] = rel);
      }
    } on FirebaseException catch (e) {
      if (mounted) _showWriteError(e);
    } catch (_) {
      if (mounted) _showWriteError(null);
    }
  }

  void _showWriteError(FirebaseException? error) {
    final l10n = AppLocalizations.of(context)!;
    final message = error?.code == 'permission-denied'
        ? l10n.authErrorTooManyRequests
        : l10n.genericError;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancelRequest(String uid, String requestId) async {
    await ref.read(friendServiceProvider).cancelRequest(requestId);
    if (!mounted) return;
    final rel = await ref.read(friendServiceProvider).getRelationship(uid);
    if (mounted) {
      setState(() => _relationships[uid] = rel);
    }
  }

  void _openProfile(AppUser user) {
    context.push<void>('/profile', extra: user).then((_) {
      // Refrescar relaciones al volver del perfil
      if (mounted && _results.isNotEmpty) {
        _refreshRelationships();
      }
    });
  }

  Future<void> _refreshRelationships() async {
    for (final user in _results) {
      try {
        final rel = await ref
            .read(friendServiceProvider)
            .getRelationship(user.uid);
        if (mounted) {
          setState(() => _relationships[user.uid] = rel);
        }
      } catch (_) {
        // Silencioso: si falla una relación en el refresh, se mantiene el valor anterior
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _hasSearched = false;
                      _relationships.clear();
                    });
                  },
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: AppTheme.pillInputBorder,
                enabledBorder: AppTheme.pillInputBorder,
                focusedBorder: AppTheme.pillInputBorder,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              autofocus: true,
              onChanged: _onSearchChanged,
            ),
          ),

          // Resultados
          Expanded(
            child: _isLoading
                ? SkeletonShimmer(
                    child: ListView(
                      children: List.generate(
                        5,
                        (_) => const SkeletonListTile(),
                      ),
                    ),
                  )
                : _hasError
                ? Center(
                    child: Text(
                      l10n.genericError,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  )
                : _results.isEmpty
                ? Center(
                    child: Text(
                      _hasSearched
                          ? l10n.searchNoResults
                          : l10n.searchTypeToSearch,
                      style: TextStyle(
                        color: colorScheme.onSurface.withAlpha(120),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final user = _results[index];
                      final photoUrl = user.photoUrl;
                      final rel = _relationships[user.uid];

                      return ListTile(
                        leading: UserCircleAvatar(
                          photoUrl: photoUrl,
                          name: user.displayName,
                        ),
                        title: Text(user.displayName),
                        subtitle: user.topArtistNames.isNotEmpty
                            ? Text(
                                user.topArtistNames.take(2).join(', '),
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: _buildTrailingAction(
                          user,
                          rel,
                          colorScheme,
                          l10n,
                        ),
                        onTap: () => _openProfile(user),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailingAction(
    AppUser user,
    RelationshipResult? rel,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    if (rel == null) {
      return Icon(
        LucideIcons.chevronRight,
        color: colorScheme.onSurfaceVariant,
      );
    }

    switch (rel.status) {
      case RelationshipStatus.friends:
        return Icon(LucideIcons.users, color: colorScheme.primary);

      case RelationshipStatus.requestSent:
        return IconButton(
          icon: Icon(
            LucideIcons.hourglass,
            color: colorScheme.onSurfaceVariant,
          ),
          tooltip: l10n.friendsRequestSent,
          onPressed: () {
            if (rel.requestId != null) {
              _cancelRequest(user.uid, rel.requestId!);
            }
          },
        );

      case RelationshipStatus.requestReceived:
        return Icon(LucideIcons.mail, color: colorScheme.primary);

      case RelationshipStatus.none:
        return IconButton(
          icon: Icon(LucideIcons.userPlus, color: colorScheme.primary),
          tooltip: l10n.friendsSendRequest,
          onPressed: () => _sendRequest(user.uid),
        );

      case RelationshipStatus.blocked:
        return Icon(LucideIcons.userX, color: colorScheme.onSurfaceVariant);
    }
  }
}
