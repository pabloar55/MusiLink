import 'package:flutter/material.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/widgets/skeleton_loader.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';

class RequestTile extends StatelessWidget {
  final String uid;
  final Future<AppUser?> Function(String) getUserFuture;
  final Widget trailing;
  final ValueChanged<AppUser>? onTap;

  const RequestTile({
    super.key,
    required this.uid,
    required this.getUserFuture,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: getUserFuture(uid),
      builder: (context, snapshot) {
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;
        if (isLoading) {
          return const SkeletonShimmer(child: SkeletonRequestTile());
        }

        final user = snapshot.data;
        final name =
            user?.displayName ?? AppLocalizations.of(context)!.socialUser;
        final photoUrl = user?.photoUrl ?? '';

        return ListTile(
          leading: UserCircleAvatar(photoUrl: photoUrl, name: name),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: trailing,
          onTap: user != null && onTap != null ? () => onTap!(user) : null,
        );
      },
    );
  }
}
