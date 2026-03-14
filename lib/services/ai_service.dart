import 'dart:convert';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';
import '../models/calendar_config.dart';
import '../tools/calendar_tools.dart';
import 'services.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String text;
  ChatMessage({required this.role, required this.text});
}

class AiService {
  AnthropicClient? _client;
  String _apiKey;
  String _model;
  List<CalendarConfig> _calendarConfigs;
  final List<InputMessage> _history = [];
  final List<ChatMessage> displayHistory = [];

  static const _maxHistory = 20;

  AiService({
    required String apiKey,
    required String model,
    required List<CalendarConfig> calendarConfigs,
  })  : _apiKey = apiKey,
        _model = model,
        _calendarConfigs = calendarConfigs {
    if (_apiKey.isNotEmpty) {
      _client = AnthropicClient.withApiKey(_apiKey);
    }
  }

  void updateConfig({
    String? apiKey,
    String? model,
    List<CalendarConfig>? calendarConfigs,
  }) {
    if (apiKey != null && apiKey != _apiKey) {
      _apiKey = apiKey;
      _client = AnthropicClient.withApiKey(_apiKey);
    }
    if (model != null) _model = model;
    if (calendarConfigs != null) _calendarConfigs = calendarConfigs;
  }

  void clearHistory() {
    _history.clear();
    displayHistory.clear();
  }

  String _buildSystemPrompt() {
    final now = DateTime.now();
    final tz = now.timeZoneName;
    final buf = StringBuffer();
    buf.writeln('You are Cadence, a helpful voice-first calendar assistant.');
    buf.writeln('Current date and time: ${now.toIso8601String()} ($tz)');
    buf.writeln('Be concise and conversational - your responses will be spoken aloud.');
    buf.writeln('');
    buf.writeln('## Calendars');
    buf.writeln('The user has the following calendars configured. Use the prompt rules to decide which calendars to search for each request:');
    for (final cal in _calendarConfigs) {
      buf.writeln('- Calendar "${cal.name}" (ID: ${cal.calendarId}): ${cal.prompt}');
    }
    buf.writeln('');
    buf.writeln('When creating events, pick the most appropriate calendar based on context, or ask the user if unclear.');
    buf.writeln('When listing events, search all calendars whose prompt rules match the request.');
    return buf.toString();
  }

  Future<String> sendMessage(String userText) async {
    if (_client == null) {
      return 'Please set your Anthropic API key in settings.';
    }

    // Add user message
    _history.add(InputMessage.user(userText));
    displayHistory.add(ChatMessage(role: 'user', text: userText));

    // Trim history
    while (_history.length > _maxHistory * 2) {
      _history.removeAt(0);
    }

    // Tool use loop
    var response = await _callClaude();
    while (response.stopReason == StopReason.toolUse) {
      // Process all tool uses in this response
      final toolResults = <InputContentBlock>[];
      for (final block in response.content) {
        if (block is ToolUseBlock) {
          final result = await _executeTool(block.name, block.input);
          toolResults.add(ToolResultInputBlock(
            toolUseId: block.id,
            content: [ToolResultContent.text(result)],
          ));
        }
      }

      // Add assistant's response (with tool use blocks) to history
      _history.add(InputMessage.assistantBlocks(
        response.content.map(_contentBlockToInput).toList(),
      ));

      // Add tool results as user message
      _history.add(InputMessage(
        role: MessageRole.user,
        content: MessageContent.blocks(toolResults),
      ));

      // Call Claude again with tool results
      response = await _callClaude();
    }

    // Extract final text response
    final text = response.text;

    // Add assistant response to history
    _history.add(InputMessage.assistantBlocks(
      response.content.map(_contentBlockToInput).toList(),
    ));
    displayHistory.add(ChatMessage(role: 'assistant', text: text));

    return text;
  }

  InputContentBlock _contentBlockToInput(ContentBlock block) {
    return switch (block) {
      TextBlock(:final text) => TextInputBlock(text),
      ToolUseBlock(:final id, :final name, :final input) =>
        ToolUseInputBlock(id: id, name: name, input: input),
      _ => TextInputBlock(''),
    };
  }

  Future<Message> _callClaude() async {
    return await _client!.messages.create(
      MessageCreateRequest(
        model: _model,
        maxTokens: 1024,
        system: SystemPrompt.text(_buildSystemPrompt()),
        tools: allTools,
        messages: _history,
      ),
    );
  }

  Future<String> _executeTool(String name, Map<String, dynamic> input) async {
    try {
      switch (name) {
        case 'list_events':
          return await _executeListEvents(input);
        case 'create_event':
          return await _executeCreateEvent(input);
        case 'update_event':
          return await _executeUpdateEvent(input);
        case 'delete_event':
          return await _executeDeleteEvent(input);
        case 'search_contacts':
          return await _executeSearchContacts(input);
        case 'add_contact':
          return await _executeAddContact(input);
        default:
          return jsonEncode({'error': 'Unknown tool: $name'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  Future<String> _executeListEvents(Map<String, dynamic> input) async {
    final calendarIds = (input['calendar_ids'] as List).cast<String>();
    final startDate = DateTime.parse(input['start_date'] as String);
    final endDate = DateTime.parse(input['end_date'] as String);

    final allEvents = <Map<String, dynamic>>[];
    for (final calId in calendarIds) {
      final events = await Services.calendar.listEvents(
        calendarId: calId,
        timeMin: startDate,
        timeMax: endDate,
      );
      for (final event in events) {
        allEvents.add({
          'calendar_id': calId,
          'event_id': event.id,
          'summary': event.summary,
          'start': event.start?.dateTime?.toIso8601String() ??
              event.start?.date?.toString(),
          'end': event.end?.dateTime?.toIso8601String() ??
              event.end?.date?.toString(),
          'description': event.description,
          'location': event.location,
        });
      }
    }
    return jsonEncode({'events': allEvents});
  }

  Future<String> _executeCreateEvent(Map<String, dynamic> input) async {
    final event = await Services.calendar.createEvent(
      calendarId: input['calendar_id'] as String,
      summary: input['summary'] as String,
      start: DateTime.parse(input['start'] as String),
      end: DateTime.parse(input['end'] as String),
      description: input['description'] as String?,
      location: input['location'] as String?,
    );
    return jsonEncode({
      'success': true,
      'event_id': event.id,
      'summary': event.summary,
    });
  }

  Future<String> _executeUpdateEvent(Map<String, dynamic> input) async {
    final event = await Services.calendar.updateEvent(
      calendarId: input['calendar_id'] as String,
      eventId: input['event_id'] as String,
      summary: input['summary'] as String?,
      start: input['start'] != null
          ? DateTime.parse(input['start'] as String)
          : null,
      end: input['end'] != null
          ? DateTime.parse(input['end'] as String)
          : null,
      description: input['description'] as String?,
      location: input['location'] as String?,
    );
    return jsonEncode({
      'success': true,
      'event_id': event.id,
      'summary': event.summary,
    });
  }

  Future<String> _executeDeleteEvent(Map<String, dynamic> input) async {
    await Services.calendar.deleteEvent(
      calendarId: input['calendar_id'] as String,
      eventId: input['event_id'] as String,
    );
    return jsonEncode({'success': true});
  }

  Future<String> _executeSearchContacts(Map<String, dynamic> input) async {
    final contacts =
        await Services.contacts.searchContacts(input['query'] as String);
    return jsonEncode({
      'contacts': contacts
          .map((c) => {'id': c.id, 'name': c.name, 'description': c.description})
          .toList(),
    });
  }

  Future<String> _executeAddContact(Map<String, dynamic> input) async {
    final id = await Services.contacts.addContact(
      input['name'] as String,
      input['description'] as String,
    );
    return jsonEncode({'success': true, 'id': id});
  }

  // Verify API key works
  static Future<bool> verifyApiKey(String apiKey) async {
    try {
      final client = AnthropicClient.withApiKey(apiKey);
      try {
        await client.messages.create(
          MessageCreateRequest(
            model: 'claude-haiku-4-5-20251001',
            maxTokens: 10,
            messages: [InputMessage.user('Hi')],
          ),
        );
        return true;
      } finally {
        client.close();
      }
    } catch (e) {
      return false;
    }
  }
}
