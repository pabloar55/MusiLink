import 'package:flutter/material.dart';
import 'package:musi_link/widgets/user_profile_photo.dart';

/// CircleAvatar del usuario con imagen + fallback de letra inicial.
class UserCircleAvatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  final double radius;

  const UserCircleAvatar({
    super.key,
    required this.photoUrl,
    required this.name,
    this.radius = 22,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      child: ClipOval(
        child: SizedBox.expand(
          child: UserProfilePhoto(
            photoUrl: photoUrl,
            fallback: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
