import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecording {
  const VoiceRecording({
    required this.bytes,
    required this.fileName,
    required this.duration,
  });

  final Uint8List bytes;
  final String fileName;
  final Duration duration;
}

class VoiceRecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw const FormatException('Разрешите доступ к микрофону.');
    }
    final directory = await getTemporaryDirectory();
    final fileName =
        'voice-${DateTime.now().toUtc().microsecondsSinceEpoch}.m4a';
    final path = '${directory.path}/$fileName';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );
    _startedAt = DateTime.now();
  }

  Future<VoiceRecording?> stop() async {
    final path = await _recorder.stop();
    final startedAt = _startedAt;
    _startedAt = null;
    if (path == null) {
      return null;
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    final fileName = path.split(Platform.pathSeparator).last;
    try {
      await file.delete();
    } catch (_) {
      // Temporary-file cleanup is best effort.
    }
    return VoiceRecording(
      bytes: bytes,
      fileName: fileName,
      duration: startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt),
    );
  }

  Future<void> cancel() async {
    _startedAt = null;
    await _recorder.cancel();
  }

  Future<void> dispose() => _recorder.dispose();
}
