import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/app_exception.dart';
import '../../data/models/account.dart';
import '../../data/repositories/auth_repository.dart';
import '../../state/media_providers.dart';
import '../../state/providers.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

/// Notifications: updates AniList reports for the signed-in account —
/// new episodes, newly added related titles and changed title data.
///
/// Guests are asked to sign in (on the profile page) since the feed is
/// tied to the AniList account.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authStateProvider);

    Widget body() {
      if (auth.isLoading && !auth.hasValue) {
        return const Center(child: CircularProgressIndicator());
      }
      final AuthUser? user = switch (auth) {
        AsyncData(:final value) => value,
        _ => null,
      };
      if (user == null) {
        return EmptyView(
          title: 'Sign in to see updates',
          message:
              'Notifications come from your AniList account: new episodes '
              'and changes for the anime you follow.',
          icon: Icons.notifications_none_outlined,
          actionLabel: 'Go to profile',
          onAction: () => context.go(Routes.profile),
        );
      }
      final feed = ref.watch(notificationsProvider);
      return feed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorView(
          message: error is AppException
              ? error.userMessage
              : 'Could not load notifications. Please try again.',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyView(
              title: 'You are all caught up',
              message: 'New episodes and updates for your anime will appear '
                  'here.',
              icon: Icons.notifications_none_outlined,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: Tokens.space48),
            itemCount: items.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: Tokens.space8),
            itemBuilder: (context, index) =>
                _NotificationTile(item: items[index]),
          );
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notifications', style: theme.textTheme.headlineMedium),
          const SizedBox(height: Tokens.space4),
          Text(
            'Updates for the anime on your AniList account.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.space16),
          Expanded(child: body()),
        ],
      ),
    );
  }
}

String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final UserNotification item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = item.coverUrl;
    final placeholder = ColoredBox(
      color: theme.disabledColor.withValues(alpha: 0.15),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () =>
            context.go(Routes.mediaDetail(item.mediaType, item.mediaId)),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space8),
          child: Row(
            spacing: Tokens.space12,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: SizedBox(
                  width: 48,
                  height: 68,
                  child: cover == null || cover.isEmpty
                      ? placeholder
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stack) => placeholder,
                        ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                    Text(
                      item.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                    Text(
                      _ago(item.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
