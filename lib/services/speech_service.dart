import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final _tts = FlutterTts();
  final _stt = stt.SpeechToText();
  bool _sttInitialized = false;
  bool _isSpeaking = false;
  final List<String> _ttsQueue = [];
  bool _processingQueue = false;
  Completer<void>? _utteranceCompleter;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _utteranceCompleter?.complete();
      _utteranceCompleter = null;
    });
  }

  Future<bool> initStt() async {
    if (_sttInitialized) return true;
    _sttInitialized = await _stt.initialize();
    return _sttInitialized;
  }

  /// Speak a complete string (non-queued, for simple use).
  Future<void> speak(String text) async {
    _isSpeaking = true;
    _utteranceCompleter = Completer<void>();
    await _tts.speak(text);
    await _utteranceCompleter!.future;
    _isSpeaking = false;
  }

  /// Queue a sentence for TTS. Sentences play one after another.
  /// Returns immediately — speech happens asynchronously.
  void queueSpeak(String text) {
    _ttsQueue.add(text);
    _isSpeaking = true;
    if (!_processingQueue) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    _processingQueue = true;
    while (_ttsQueue.isNotEmpty) {
      final sentence = _ttsQueue.removeAt(0);
      _utteranceCompleter = Completer<void>();
      await _tts.speak(sentence);
      await _utteranceCompleter!.future;
    }
    _processingQueue = false;
    _isSpeaking = false;
  }

  Future<void> stopSpeaking() async {
    _ttsQueue.clear();
    _processingQueue = false;
    _isSpeaking = false;
    _utteranceCompleter?.complete();
    _utteranceCompleter = null;
    await _tts.stop();
  }

  Future<void> listen({
    required void Function(String text) onResult,
    required void Function() onDone,
    void Function(String error)? onError,
  }) async {
    // Stop TTS before listening to prevent feedback loop
    await stopSpeaking();

    final available = await initStt();
    if (!available) {
      onError?.call('Speech recognition not available');
      return;
    }

    await _stt.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
          onDone();
        }
      },
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stopListening() async {
    await _stt.stop();
  }

  bool get isListening => _stt.isListening;
}
