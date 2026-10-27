import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/repositories/auth_repository.dart';
import '../../state/providers.dart';
import '../router/app_router.dart';
import '../screens/settings_dialog.dart';
import 'sign_in_dialog.dart';

/// Top-bar account control.
///
/// - **Desktop, guest:** a **Sign in** button (icon only on tighter bars).
/// - **Desktop, signed in:** the AniList avatar; its menu has **Profile** and
///   **Sign out**. Settings and History live in the sidebar there.
/// - **Mobile:** the avatar (or a person icon for guests). The menu has
///   **Settings**, **History** and **Sign out** (**Sign in** for guests),
///   because phones have no sidebar. The name header opens the profile.
///
/// Keeping it here (rather than on the profile page) means sign in / sign out
/// is reachable from every screen and there is a single source of truth.
class AccountButton extends ConsumerWidget {
  const AccountButton({this.iconOnly = false, this.mobile = false, super.key});

  /// When true the desktop guest button collapses to an icon to save space.
  final bool iconOnly;

  /// Phone layout: the menu carries Settings and History.
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final AuthUser? user = switch (auth) {
      AsyncData(:final value) => value,
      _ => null,
    };

    if (user == null) {
      // While the saved session is being validated, hold the slot so the bar
      // does not flash between "Sign in" and the avatar.
      if (auth.isLoading && !auth.hasValue) {
        return const SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (mobile) return const _GuestMenu();
      if (iconOnly) {
        return IconButton(
          tooltip: 'Sign in with AniList',
          icon: const Icon(Icons.login_rounded),
          onPressed: () => showSignInDialog(context),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        child: FilledButton.icon(
          onPressed: () => showSignInDialog(context),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Sign in'),
        ),
      );
    }

    return _UserMenu(user: user, mobile: mobile);
  }
}

/// Phone menu for guests: the same shortcuts, with Sign in at the end.
class _GuestMenu extends StatelessWidget {
  const _GuestMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_outlined),
      offset: const Offset(0, 46),
      onSelected: (value) {
        switch (value) {
          case 'settings':
            showSettingsDialog(context);
          case 'history':
            context.go(Routes.history);
          case 'signin':
            showSignInDialog(context);
        }
      },
      itemBuilder: (context) => [
        _menuRow('settings', Icons.settings_outlined, 'Settings'),
        _menuRow('history', Icons.history_rounded, 'History'),
        const PopupMenuDivider(),
        _menuRow('signin', Icons.login_rounded, 'Sign in'),
      ],
    );
  }
}

/// One icon + label row in an account popup menu.
PopupMenuItem<String> _menuRow(String value, IconData icon, String label) {
  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: Tokens.space12),
        Text(label),
      ],
    ),
  );
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user, required this.mobile});

  final AuthUser user;
  final bool mobile;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authRepositoryProvider).signOut();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed out')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<String>(
      tooltip: user.name,
      offset: const Offset(0, 46),
      onSelected: (value) {
        switch (value) {
          case 'profile':
            context.go(Routes.profile);
          case 'settings':
            showSettingsDialog(context);
          case 'history':
            context.go(Routes.history);
          case 'signout':
            _signOut(context, ref);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'profile',
          height: 64,
          child: Row(
            children: [
              _Avatar(user: user, size: 30),
              const SizedBox(width: Tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      'Signed in with AniList',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (mobile) ...[
          _menuRow('settings', Icons.settings_outlined, 'Settings'),
          _menuRow('history', Icons.history_rounded, 'History'),
        ] else
          _menuRow('profile', Icons.person_outline, 'Profile'),
        const PopupMenuDivider(),
        _menuRow('signout', Icons.logout_rounded, 'Sign out'),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        child: _Avatar(user: user, size: 32),
      ),
    );
  }
}

/// Round AniList avatar with an initial-letter fallback.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.size});

  final AuthUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = user.avatarUrl;
    final initial = user.name.isEmpty
        ? '?'
        : user.name.substring(0, 1).toUpperCase();
    final fallback = ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHighest,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: url == null || url.isEmpty
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => fallback,
            ),
    );
  }
}
