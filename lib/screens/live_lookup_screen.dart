import 'package:flutter/material.dart';

import '../core/network/error_parser.dart';
import '../models/video_models.dart';
import '../repositories/live_repository.dart';
import 'live_view_screen.dart';

class LiveLookupScreen extends StatefulWidget {
  final LiveRepository liveRepository;

  const LiveLookupScreen({
    super.key,
    required this.liveRepository,
  });

  @override
  State<LiveLookupScreen> createState() => _LiveLookupScreenState();
}

class _LiveLookupScreenState extends State<LiveLookupScreen> {
  bool loading = false;
  String? error;
  List<ActiveLiveListItem> streams = const [];
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadStreams();
  }

  Future<void> loadStreams() async {
    if (loading) return;

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final result = await widget.liveRepository.getActiveStreams();

      if (!mounted) return;

      setState(() {
        streams = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        error = NetworkErrorMapper.map(
          e,
          fallbackMessage: 'Failed to load live streams.',
        );
        loading = false;
      });
    }
  }

  List<ActiveLiveListItem> get filteredStreams {
    final query = searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return streams;
    }

    return streams.where((item) {
      final title = item.title.toLowerCase();
      final owner = (item.ownerName ?? '').toLowerCase();
      final description = (item.description ?? '').toLowerCase();

      return title.contains(query) ||
          owner.contains(query) ||
          description.contains(query);
    }).toList();
  }

  Future<void> openLiveItem(ActiveLiveListItem item) async {
    final hlsUrl = item.hlsUrl?.trim() ?? '';

    if (hlsUrl.isEmpty) {
      setState(() {
        error = 'HLS URL is missing for the selected stream.';
      });
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveViewScreen(
          liveRepository: widget.liveRepository,
          title: item.title,
          streamKey: item.streamKey,
          hlsUrl: hlsUrl,
          status: item.status,
        ),
      ),
    );
  }

  String _formatStartedAt(DateTime? value) {
    if (value == null) return '—';

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day.$month.$year $hour:$minute';
  }

  Widget _buildSearch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search by title or owner',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          suffixIcon: searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    setState(() {
                      searchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.clear, color: Colors.white70),
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
        style: const TextStyle(color: Colors.white),
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildSearchEmptyState() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Nothing found',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    searchQuery = '';
                  });
                },
                child: const Text('Clear search'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateBlock() {
    final filtered = filteredStreams;
    final hasSearch = searchQuery.trim().isNotEmpty;

    if (loading && streams.isEmpty) {
      return const Expanded(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null && streams.isEmpty) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: loadStreams,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (streams.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text('No live streams now'),
        ),
      );
    }

    if (filtered.isEmpty && hasSearch) {
      return _buildSearchEmptyState();
    }

    return Expanded(
      child: RefreshIndicator(
        onRefresh: loadStreams,
        child: ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = filtered[index];

            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const CircleAvatar(
                  child: Icon(Icons.live_tv),
                ),
                title: Text(item.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((item.ownerName ?? '').isNotEmpty)
                      Text('Owner: ${item.ownerName}'),
                    Text('Started: ${_formatStartedAt(item.startedAt)}'),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openLiveItem(item),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasInlineError = error != null && streams.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live streams'),
        actions: [
          IconButton(
            onPressed: loading ? null : loadStreams,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSearch(),
            const SizedBox(height: 16),
            if (loading && streams.isNotEmpty) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            if (hasInlineError) ...[
              Text(
                error!,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 12),
            ],
            _buildStateBlock(),
          ],
        ),
      ),
    );
  }
}