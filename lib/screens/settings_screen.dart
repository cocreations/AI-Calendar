import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import '../services/services.dart';
import '../services/storage_service.dart';
import '../services/contacts_service.dart';
import '../models/calendar_config.dart';
import 'setup_screen.dart';
import 'background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currentModel = StorageService.defaultModel;
  String? _apiKey;
  List<CalendarConfig> _calendars = [];
  List<Contact> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _currentModel = await Services.storage.getModel();
    _apiKey = await Services.storage.getApiKey();
    _calendars = await Services.storage.getCalendarConfigs();
    _contacts = await Services.contacts.getAllContacts();
    setState(() => _loading = false);
  }

  Future<void> _changeModel(String model) async {
    await Services.storage.setModel(model);
    Services.ai.updateConfig(model: model);
    setState(() => _currentModel = model);
  }

  Future<void> _updateApiKey() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update API Key'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'sk-ant-...',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                Navigator.pop(ctx);
              } else {
                Navigator.pop(ctx, text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await Services.storage.setApiKey(result);
      Services.ai.updateConfig(apiKey: result);
      setState(() => _apiKey = result);
    }
  }

  Future<void> _signOut() async {
    await Services.calendar.signOut();
    await Services.storage.setCalendarConfigs([]);
    await Services.storage.deleteApiKey();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SetupScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _addCalendar() async {
    try {
      final available = await Services.calendar.listCalendars();
      final existing = _calendars.map((c) => c.calendarId).toSet();
      final unlinked =
          available.where((c) => !existing.contains(c.id)).toList();

      if (unlinked.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All calendars are already linked.')),
          );
        }
        return;
      }

      if (!mounted) return;
      final selected = await showDialog<gcal.CalendarListEntry>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Add Calendar'),
          children: unlinked.map((cal) {
            return SimpleDialogOption(
              child: Text(cal.summary ?? cal.id ?? ''),
              onPressed: () => Navigator.pop(ctx, cal),
            );
          }).toList(),
        ),
      );

      if (selected == null || !mounted) return;

      // Ask for prompt
      final promptController = TextEditingController(
        text: 'Search this calendar when relevant',
      );
      final prompt = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Rule for "${selected.summary}"'),
          content: TextField(
            controller: promptController,
            decoration: const InputDecoration(
              labelText: 'When should the AI search this calendar?',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = promptController.text.trim();
                if (text.isEmpty) {
                  Navigator.pop(ctx);
                } else {
                  Navigator.pop(ctx, text);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (prompt != null && prompt.isNotEmpty) {
        final config = CalendarConfig(
          calendarId: selected.id ?? '',
          name: selected.summary ?? selected.id ?? '',
          prompt: prompt,
        );
        await Services.storage.addCalendarConfig(config);
        await Services.reinitAi();
        await _loadSettings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _removeCalendar(String calendarId) async {
    await Services.storage.removeCalendarConfig(calendarId);
    await Services.reinitAi();
    await _loadSettings();
  }

  Future<void> _editCalendarPrompt(CalendarConfig cal) async {
    final controller = TextEditingController(text: cal.prompt);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit rule for "${cal.name}"'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'When should the AI search this calendar?',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) {
                Navigator.pop(ctx);
              } else {
                Navigator.pop(ctx, text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await Services.storage.updateCalendarPrompt(cal.calendarId, result);
      await Services.reinitAi();
      await _loadSettings();
    }
  }

  Future<void> _deleteContact(Contact contact) async {
    if (contact.id == null) return;
    await Services.contacts.deleteContact(contact.id!);
    await _loadSettings();
  }

  void _clearConversation() {
    Services.ai.clearHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Conversation cleared.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Settings'),
            backgroundColor: Colors.black45,
            foregroundColor: Colors.white,
          ),
          body: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Settings'),
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
        ),
        body: ListView(
        children: [
          _buildSection('AI Model', [
            RadioGroup<String>(
              groupValue: _currentModel,
              onChanged: (val) { if (val != null) _changeModel(val); },
              child: Column(
                children: StorageService.modelOptions.map((opt) {
                  final id = opt['id']!;
                  return RadioListTile<String>(
                    title: Text(opt['label']!),
                    subtitle: Text(id, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    value: id,
                  );
                }).toList(),
              ),
            ),
          ]),
          _buildSection('Anthropic API Key', [
            ListTile(
              title: Text(_apiKey != null && _apiKey!.length > 8
                  ? '${_apiKey!.substring(0, 8)}...'
                  : 'Not set'),
              trailing: TextButton(
                onPressed: _updateApiKey,
                child: const Text('Update'),
              ),
            ),
          ]),
          _buildSection('Google Account', [
            ListTile(
              title: Text(Services.calendar.userEmail ?? 'Not signed in'),
              trailing: TextButton(
                onPressed: _signOut,
                child: const Text('Sign Out'),
              ),
            ),
          ]),
          _buildSection('Calendars', [
            ..._calendars.map((cal) => ListTile(
                  title: Text(cal.name),
                  subtitle: Text(cal.prompt,
                      style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _editCalendarPrompt(cal),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _removeCalendar(cal.calendarId),
                      ),
                    ],
                  ),
                )),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add Calendar'),
              onTap: _addCalendar,
            ),
          ]),
          _buildSection('Contacts', [
            if (_contacts.isEmpty)
              const ListTile(
                title: Text('No contacts saved yet',
                    style: TextStyle(color: Colors.grey)),
              ),
            ..._contacts.map((c) => ListTile(
                  title: Text(c.name),
                  subtitle: Text(c.description),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () => _deleteContact(c),
                  ),
                )),
          ]),
          _buildSection('Conversation', [
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Clear Conversation History'),
              onTap: _clearConversation,
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.lightBlueAccent,
              ),
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(
              listTileTheme: const ListTileThemeData(
                textColor: Colors.white,
                iconColor: Colors.white70,
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

