import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  final _tts = FlutterTts();
  final _stt = stt.SpeechToText();
  bool _sttInitialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  Future<void> init() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }

  Future<bool> initStt() async {
    if (_sttInitialized) return true;
    _sttInitialized = await _stt.initialize();
    return _sttInitialized;
  }

  Future<void> speak(String text) async {
    _isSpeaking = true;
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    _isSpeaking = false;
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
