import 'package:flutter/material.dart';

import '../models/visited_page.dart';
import '../services/recent_sites_service.dart';

/// Where the tapped page should open.
enum StartpageOpenTarget { currentTab, newTab }

/// Modern, minimal browser Startpage: search/URL field, bookmarks shortcut
/// slot, and the last-10 visited pages with favicon/title/domain.
///
/// Follows the system light/dark theme via [Theme.of] (no hardcoded
/// brightness). States: empty / loading / error / populated, plus per-row
/// favicon fallback when the icon cannot load.
class StartpageView extends StatelessWidget {
  /// Resolve a search/URL input to a navigable URL. Pure + unit-tested:
  /// bare domains get `https://`, multi-word input becomes a search URL.
  static String resolveSearchUrl(String input) {
    final t = input.trim();
    if (t.isEmpty) return '';
    if (t.contains(' ') || !t.contains('.')) {
      return 'https://duckduckgo.com/?q=${Uri.encodeComponent(t)}';
    }
    if (t.startsWith('http://') ||
        t.startsWith('https://') ||
        t.startsWith('oct://')) {
      return t;
    }
    return 'https://$t';
  }

  final bool isLoading;
  final String? error;
  final List<VisitedPage> pages;
  final List<Map<String, String>> bookmarks;
  final Future<void> Function(String url, StartpageOpenTarget target) onOpen;
  final Future<void> Function(String url) onDelete;
  final Future<void> Function() onClearAll;
  final Future<void> Function()? onRetry;
  final void Function(String query)? onSearch;
  final VoidCallback? onBookmarksTap;

  const StartpageView({
    super.key,
    required this.isLoading,
    required this.error,
    required this.pages,
    required this.bookmarks,
    required this.onOpen,
    required this.onDelete,
    required this.onClearAll,
    this.onRetry,
    this.onSearch,
    this.onBookmarksTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Search + URL field.
          _SearchBar(onSearch: onSearch),
          const SizedBox(height: 16),
          // Bookmarks strip.
          Row(
            children: [
              Text('Bookmarks',
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (onBookmarksTap != null)
                TextButton(
                    onPressed: onBookmarksTap, child: const Text('Manage')),
            ],
          ),
          const SizedBox(height: 8),
          if (bookmarks.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.bookmark_border_rounded,
                      color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('No bookmarks yet',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: bookmarks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final b = bookmarks[i];
                  final url = b['url'] ?? '';
                  final name = b['name'] ?? url;
                  return _BookmarkChip(
                    name: name,
                    url: url,
                    onTap: () => onOpen(url, StartpageOpenTarget.currentTab),
                  );
                },
              ),
            ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Recent',
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${pages.length}/${RecentSitesService.maxEntries}',
                  style:
                      TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const Spacer(),
              if (pages.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClearAll(context),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: const Text('Clear all'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (isLoading)
            const _LoadingList()
          else if (error != null)
            _ErrorState(message: error!, onRetry: onRetry)
          else if (pages.isEmpty)
            const _EmptyState()
          else
            ...pages.map((p) => _RecentRow(
                  page: p,
                  onOpen: onOpen,
                  onDelete: onDelete,
                )),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
            'Delete all recently visited sites from this device?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true) await onClearAll();
  }
}

class _SearchBar extends StatefulWidget {
  final void Function(String query)? onSearch;
  const _SearchBar({this.onSearch});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static String resolveQuery(String input) => StartpageView.resolveSearchUrl(input);

  Future<void> _go() async {
    final fn = widget.onSearch;
    if (fn == null || _busy) return;
    final q = _ctrl.text;
    if (q.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await fn(resolveQuery(q));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        hintText: 'Search or enter URL',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _busy
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _go,
                tooltip: 'Go',
              ),
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _go(),
    );
  }
}

class _BookmarkChip extends StatelessWidget {
  final String name;
  final String url;
  final VoidCallback onTap;
  const _BookmarkChip(
      {required this.name, required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Favicon(url: url, size: 22),
            const SizedBox(height: 6),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
            Text(VisitedPage.domainOf(url),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  final VisitedPage page;
  final Future<void> Function(String url, StartpageOpenTarget target) onOpen;
  final Future<void> Function(String url) onDelete;
  const _RecentRow(
      {required this.page, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        leading: _Favicon(url: page.url, size: 26),
        title: Text(
          page.title.isEmpty ? page.domain : page.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(page.domain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          onSelected: (v) async {
            switch (v) {
              case 'open':
                await onOpen(page.url, StartpageOpenTarget.currentTab);
                break;
              case 'new_tab':
                await onOpen(page.url, StartpageOpenTarget.newTab);
                break;
              case 'delete':
                await onDelete(page.url);
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(value: 'new_tab', child: Text('Open in new tab')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => onOpen(page.url, StartpageOpenTarget.currentTab),
      ),
    );
  }
}

class _Favicon extends StatefulWidget {
  final String url;
  final double size;
  const _Favicon({required this.url, required this.size});

  @override
  State<_Favicon> createState() => _FaviconState();
}

class _FaviconState extends State<_Favicon> {
  bool _failed = false;

  static String faviconUrl(String pageUrl) {
    try {
      final uri = Uri.parse(pageUrl);
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) {
        return '${uri.scheme}://${uri.host}/favicon.ico';
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fav = faviconUrl(widget.url);
    final fallback = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.language_rounded,
          size: widget.size * 0.6, color: cs.primary),
    );
    if (fav.isEmpty || _failed) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        fav,
        width: widget.size,
        height: widget.size,
        errorBuilder: (_, __, ___) {
          if (!_failed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _failed = true);
            });
          }
          return fallback;
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(Icons.explore_outlined,
              size: 44, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          const Text('No recent sites yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          Text('Pages you visit will appear here.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        3,
        (i) => Container(
          height: 64,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;
  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, color: cs.error, size: 32),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}
