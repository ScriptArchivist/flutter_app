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
          fallbackMessage: 'Не удалось загрузить список live-стримов.',
        );
        loading = false;
      });
    }
  }

  Future<void> openLiveItem(ActiveLiveListItem item) async {
    final hlsUrl = item.hlsUrl?.trim() ?? '';

    if (hlsUrl.isEmpty) {
      setState(() {
        error = 'Для выбранного стрима отсутствует HLS URL.';
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

  Widget _buildStateBlock() {
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
                  child: const Text('Повторить'),
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
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Сейчас нет активных live-стримов.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: RefreshIndicator(
        onRefresh: loadStreams,
        child: ListView.separated(
          itemCount: streams.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = streams[index];

            return Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const CircleAvatar(
                  child: Icon(Icons.live_tv),
                ),
                title: Text(item.title),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: ${item.status}'),
                      Text('HLS ready: ${item.hlsReady ? "yes" : "no"}'),
                      if ((item.ownerName ?? '').isNotEmpty)
                        Text('Owner: ${item.ownerName}'),
                      Text('Started: ${_formatStartedAt(item.startedAt)}'),
                      if ((item.description ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            item.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Активные стримы',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            _buildStateBlock(),
          ],
        ),
      ),
    );
  }
}