import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:url_launcher/url_launcher.dart';
import '../services/services.dart';
import '../models/calendar_config.dart';
import '../services/ai_service.dart';
import 'voice_screen.dart';
import 'background.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0; // 0=google, 1=apikey, 2=calendars
  final _apiKeyController = TextEditingController();
  bool _verifying = false;
  bool _googleSigningIn = false;
  List<gcal.CalendarListEntry> _availableCalendars = [];
  final Set<String> _selectedCalendarIds = {};
  bool _loadingCalendars = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleSigningIn = true);
    final success = await Services.calendar.signIn();
    setState(() => _googleSigningIn = false);

    if (success) {
      setState(() => _step = 1);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _verifyApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;

    setState(() => _verifying = true);
    final valid = await AiService.verifyApiKey(key);
    setState(() => _verifying = false);

    if (valid) {
      await Services.storage.setApiKey(key);
      await _loadCalendars();
      setState(() => _step = 2);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid API key. Please check and try again.')),
        );
      }
    }
  }

  Future<void> _loadCalendars() async {
    setState(() => _loadingCalendars = true);
    try {
      _availableCalendars = await Services.calendar.listCalendars();
    } catch (e) {
      _availableCalendars = [];
    }
    setState(() => _loadingCalendars = false);
  }

  Future<void> _finishSetup() async {
    final configs = <CalendarConfig>[];
    for (final id in _selectedCalendarIds) {
      final cal = _availableCalendars.firstWhere((c) => c.id == id);
      configs.add(CalendarConfig(
        calendarId: id,
        name: cal.summary ?? id,
        prompt: configs.isEmpty
            ? 'Always search this calendar'
            : 'Search this calendar when relevant',
      ));
    }
    await Services.storage.setCalendarConfigs(configs);
    await Services.reinitAi();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VoiceScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Cadence Setup'),
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            0 => _buildGoogleStep(),
            1 => _buildApiKeyStep(),
            2 => _buildCalendarStep(),
            _ => const SizedBox(),
          },
        ),
      ),
    );
  }

  Widget _buildGoogleStep() {
    return Center(
      child: _card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.calendar_month, size: 80, color: Colors.blue),
            const SizedBox(height: 24),
            const Text(
              'Welcome to Cadence',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'First, sign in with Google to access your calendars.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _googleSigningIn ? null : _signInWithGoogle,
              icon: _googleSigningIn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_googleSigningIn ? 'Signing in...' : 'Sign in with Google'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyStep() {
    return Center(
      child: _card(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.key, size: 80, color: Colors.orange),
            const SizedBox(height: 24),
            const Text(
              'Anthropic API Key',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Enter your Anthropic API key to power the AI assistant.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _apiKeyController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'API Key',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'sk-ant-...',
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white38),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                launchUrl(
                  Uri.parse('https://console.anthropic.com/settings/keys'),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('Get an API key at console.anthropic.com'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _verifying ? null : _verifyApiKey,
              child: _verifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verify & Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarStep() {
    if (_loadingCalendars) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return _card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select Calendars',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose which calendars the AI should have access to.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _availableCalendars.length,
              itemBuilder: (context, index) {
                final cal = _availableCalendars[index];
                final id = cal.id ?? '';
                return CheckboxListTile(
                  title: Text(cal.summary ?? id, style: const TextStyle(color: Colors.white)),
                  subtitle: Text(id, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  value: _selectedCalendarIds.contains(id),
                  checkColor: Colors.white,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedCalendarIds.add(id);
                      } else {
                        _selectedCalendarIds.remove(id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _selectedCalendarIds.isEmpty ? null : _finishSetup,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Get Started'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}
