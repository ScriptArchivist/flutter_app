import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../repositories/upload_repository.dart';
import '../repositories/video_repository.dart';
import 'video_detail_screen.dart';

class UploadScreen extends StatefulWidget {
  final VideoRepository videoRepository;
  final UploadRepository uploadRepository;

  const UploadScreen({
    super.key,
    required this.videoRepository,
    required this.uploadRepository,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  VideoRepository get videoRepository => widget.videoRepository;
  UploadRepository get uploadRepository => widget.uploadRepository;

  final titleController = TextEditingController();
  final descriptionController = TextEditingController();

  String visibility = 'private';
  String? selectedFilePath;
  String? selectedFilename;

  bool loading = false;
  bool uploadStarted = false;
  bool navigationDone = false;

  String? error;
  String statusText = '';

  Timer? pollingTimer;
  int? createdVideoId;
  int pollingAttempts = 0;

  static const int maxPollingAttempts = 120;

  Future<void> pickVideo() async {
    if (loading) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final path = file.path;

      if (path == null || path.trim().isEmpty) {
        setState(() {
          error = 'Не удалось получить путь к выбранному файлу';
        });
        return;
      }

      setState(() {
        selectedFilePath = path;
        selectedFilename = file.name;
        error = null;
      });
    } catch (e) {
      setState(() {
        error = 'Не удалось выбрать файл: $e';
      });
    }
  }

  Future<void> startUpload() async {
    if (loading || uploadStarted) return;

    final filePath = selectedFilePath?.trim() ?? '';
    if (filePath.isEmpty) {
      setState(() {
        error = 'Сначала выберите видеофайл';
      });
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      setState(() {
        error = 'Файл не найден: $filePath';
      });
      return;
    }

    final title = titleController.text.trim();
    if (title.isEmpty) {
      setState(() {
        error = 'Укажите title';
      });
      return;
    }

    pollingTimer?.cancel();
    pollingAttempts = 0;
    navigationDone = false;
    createdVideoId = null;

    setState(() {
      loading = true;
      uploadStarted = true;
      error = null;
      statusText = 'Creating video metadata...';
    });

    try {
      final filename = selectedFilename ?? p.basename(filePath);
      final fileSize = await file.length();
      final contentType = lookupMimeType(filePath) ?? 'application/octet-stream';

      final video = await videoRepository.createVideo(
        title: title,
        description: descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim(),
        visibility: visibility,
      );

      final videoId = video['id'] as int;
      createdVideoId = videoId;

      setState(() {
        statusText = 'Init upload...';
      });

      final uploadId = await uploadRepository.initUpload(
        videoId: videoId,
        filename: filename,
      );

      setState(() {
        statusText = 'Uploading file...';
      });

      await uploadRepository.uploadFile(
        uploadId: uploadId,
        filePath: filePath,
        filename: filename,
      );

      setState(() {
        statusText = 'Completing upload...';
      });

      await uploadRepository.completeUpload(
        uploadId: uploadId,
        size: fileSize,
        contentType: contentType,
      );

      setState(() {
        statusText = 'Upload completed. Polling video status...';
      });

      await checkVideoStatusOnce(videoId);
      if (!navigationDone) {
        startPolling(videoId);
      }
    } catch (e) {
      setState(() {
        error = 'Upload failed: $e';
        loading = false;
        uploadStarted = false;
      });
    }
  }

  Future<void> checkVideoStatusOnce(int videoId) async {
    final video = await videoRepository.getVideo(videoId, consistent: true);
    final status = video['status']?.toString() ?? '';

    setState(() {
      statusText = 'Current status: $status';
    });

    await handleTerminalStatus(videoId, video, status);
  }

  void startPolling(int videoId) {
    pollingTimer?.cancel();
    pollingAttempts = 0;

    pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      pollingAttempts += 1;
      if (pollingAttempts > maxPollingAttempts) {
        timer.cancel();
        setState(() {
          loading = false;
          uploadStarted = false;
          error = 'Видео слишком долго не переходит в ready';
        });
        return;
      }

      final video = await videoRepository.getVideo(videoId, consistent: true);
      final status = video['status']?.toString() ?? '';

      setState(() {
        statusText =
            'Current status: $status ($pollingAttempts/$maxPollingAttempts)';
      });

      final handled = await handleTerminalStatus(videoId, video, status);
      if (handled) {
        timer.cancel();
      }
    });
  }

  Future<bool> handleTerminalStatus(
    int videoId,
    Map<String, dynamic> video,
    String status,
  ) async {
    if (status == 'failed') {
      pollingTimer?.cancel();
      setState(() {
        loading = false;
        uploadStarted = false;
        error = 'Processing failed';
      });
      return true;
    }

    if (status == 'ready') {
      pollingTimer?.cancel();
      setState(() {
        loading = false;
        uploadStarted = false;
      });

      if (!navigationDone) {
        navigationDone = true;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => VideoDetailScreen(
              videoId: videoId,
              videoRepository: videoRepository,
            ),
          ),
        );
      }
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    pollingTimer?.cancel();
    titleController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filename = selectedFilename ?? 'Файл не выбран';

    return Scaffold(
      appBar: AppBar(title: const Text('Upload video')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: titleController,
              enabled: !loading,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descriptionController,
              enabled: !loading,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: visibility,
              items: const [
                DropdownMenuItem(value: 'private', child: Text('private')),
                DropdownMenuItem(value: 'public', child: Text('public')),
                DropdownMenuItem(value: 'unlisted', child: Text('unlisted')),
              ],
              onChanged: loading
                  ? null
                  : (v) {
                      if (v != null) {
                        setState(() {
                          visibility = v;
                        });
                      }
                    },
              decoration: const InputDecoration(
                labelText: 'Visibility',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Выбранный файл: $filename'),
            if (selectedFilePath != null) ...[
              const SizedBox(height: 8),
              SelectableText(selectedFilePath!),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: loading ? null : pickVideo,
                child: const Text('Выбрать видео'),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : startUpload,
                child: loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start upload'),
              ),
            ),
            const SizedBox(height: 16),
            if (statusText.isNotEmpty) Text(statusText),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}