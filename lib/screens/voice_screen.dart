import 'package:flutter/material.dart';
import '../services/services.dart';
import '../services/ai_service.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'background.dart';

enum VoiceState { idle, listening, thinking, speaking }

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with SingleTickerProviderStateMixin {
  VoiceState _state = VoiceState.idle;
  late AnimationController _pulseController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ChatMessage> get _messages => Services.ai.displayHistory;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startListening() async {
    await Services.speech.stopSpeaking();
    setState(() => _state = VoiceState.listening);
    _pulseController.repeat(reverse: true);

    await Services.speech.listen(
      onResult: (text) async {
        _pulseController.stop();
        _pulseController.reset();
        setState(() => _state = VoiceState.thinking);
        _scrollToBottom();

        try {
          bool firstSentence = true;
          await Services.ai.sendMessage(
            text,
            onSentence: (sentence) {
              if (firstSentence) {
                firstSentence = false;
                if (mounted) {
                  setState(() => _state = VoiceState.speaking);
                }
              }
              Services.speech.queueSpeak(sentence);
            },
          );
          if (mounted) {
            setState(() => _state = VoiceState.speaking);
          }
          _scrollToBottom();

          // Wait for TTS queue to drain
          while (Services.speech.isSpeaking) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }

        if (mounted) {
          setState(() => _state = VoiceState.idle);
        }
      },
      onDone: () {
        // Handled in onResult
      },
      onError: (error) {
        _pulseController.stop();
        _pulseController.reset();
        if (mounted) {
          setState(() => _state = VoiceState.idle);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech error: $error')),
          );
        }
      },
    );
  }

  Future<void> _stopListening() async {
    await Services.speech.stopListening();
    _pulseController.stop();
    _pulseController.reset();
    setState(() => _state = VoiceState.idle);
  }

  Future<void> _stopSpeaking() async {
    await Services.speech.stopSpeaking();
    setState(() => _state = VoiceState.idle);
  }

  void _onMicPressed() {
    switch (_state) {
      case VoiceState.idle:
        _startListening();
      case VoiceState.listening:
        _stopListening();
      case VoiceState.speaking:
        _stopSpeaking();
      case VoiceState.thinking:
        break; // Can't interrupt thinking
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Cadence'),
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.favorite_border),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                // Refresh in case settings changed
                setState(() {});
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildConversation()),
            _buildStateIndicator(),
            _buildMicButton(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildConversation() {
    if (_messages.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'Tap the microphone and ask about your calendar',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isUser = msg.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? Colors.blue.withAlpha(200)
                  : Colors.black.withAlpha(180),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              msg.text,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStateIndicator() {
    final (text, color) = switch (_state) {
      VoiceState.idle => ('', Colors.transparent),
      VoiceState.listening => ('Listening...', Colors.red),
      VoiceState.thinking => ('Thinking...', Colors.orange),
      VoiceState.speaking => ('Speaking...', Colors.green),
    };

    if (_state == VoiceState.idle) return const SizedBox(height: 24);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_state == VoiceState.thinking)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    final isActive = _state == VoiceState.listening;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = isActive ? 1.0 + _pulseController.value * 0.2 : 1.0;
        return Transform.scale(
          scale: scale,
          child: FloatingActionButton.large(
            onPressed: _state == VoiceState.thinking ? null : _onMicPressed,
            backgroundColor: switch (_state) {
              VoiceState.idle => Theme.of(context).colorScheme.primary,
              VoiceState.listening => Colors.red,
              VoiceState.thinking => Colors.grey,
              VoiceState.speaking => Colors.green,
            },
            child: Icon(
              switch (_state) {
                VoiceState.idle => Icons.mic,
                VoiceState.listening => Icons.stop,
                VoiceState.thinking => Icons.hourglass_top,
                VoiceState.speaking => Icons.stop,
              },
              size: 36,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }
}
