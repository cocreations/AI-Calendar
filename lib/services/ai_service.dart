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
  String? _cachedEventsSummary;

  static const _maxHistory = 20;
  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  static String _dayOfWeek(DateTime dt) => _weekdays[dt.weekday - 1];

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

  /// Pre-fetch today's and tomorrow's events from always-search calendars.
  /// Embeds them in the system prompt so Claude can answer without tool calls.
  Future<void> refreshEventCache() async {
    if (!Services.calendar.isSignedIn) return;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final tomorrowEnd = todayStart.add(const Duration(days: 2));

    final allEvents = <Map<String, dynamic>>[];
    for (final cal in _calendarConfigs) {
      if (cal.prompt.toLowerCase().contains('always')) {
        try {
          final events = await Services.calendar.listEvents(
            calendarId: cal.calendarId,
            timeMin: todayStart,
            timeMax: tomorrowEnd,
          );
          for (final event in events) {
            final dt = (event.start?.dateTime ?? event.start?.date)
                ?.toLocal();
            allEvents.add({
              'summary': event.summary,
              'start': dt?.toIso8601String(),
              'day': dt != null ? _dayOfWeek(dt) : null,
            });
          }
        } catch (_) {}
      }
    }

    if (allEvents.isEmpty) {
      _cachedEventsSummary = null;
      return;
    }

    final buf = StringBuffer();
    buf.writeln('## Pre-fetched events (today and tomorrow)');
    buf.writeln(
        'Use this to answer simple queries without calling list_events:');
    for (final e in allEvents) {
      buf.writeln('- ${e['day'] ?? ''} ${e['start']}: ${e['summary']}');
    }
    _cachedEventsSummary = buf.toString();
  }

  String _buildSystemPrompt() {
    final now = DateTime.now();
    final tz = now.timeZoneName;
    final dayName = _dayOfWeek(now);
    final buf = StringBuffer();
    buf.writeln('You are Cadence, a helpful voice-first calendar assistant.');
    buf.writeln(
        'Current date and time: $dayName, ${now.toIso8601String()} ($tz)');
    buf.writeln('Your responses are spoken aloud. Keep them short and direct.');
    buf.writeln(
        'Skip preamble that restates context the user already knows (e.g. "Looking at your calendar", "Here\'s what you have this week", "For today"). Just give the answer directly.');
    buf.writeln(
        'Do NOT end with a follow-up question (e.g. "Would you like me to…?", "Anything else?"). Just stop after the information or confirmation.');
    buf.writeln(
        'When mentioning dates, ALWAYS use the day_of_week field from event data. Never guess the day of week.');
    buf.writeln(
        'All event times are in the user\'s local timezone ($tz). Use them directly — do not convert.');
    buf.writeln('');
    buf.writeln('## Calendars');
    buf.writeln(
        'The user has the following calendars configured. Use the prompt rules to decide which calendars to search for each request:');
    for (final cal in _calendarConfigs) {
      buf.writeln(
          '- Calendar "${cal.name}" (ID: ${cal.calendarId}): ${cal.prompt}');
    }
    buf.writeln('');
    buf.writeln(
        'When creating events, pick the most appropriate calendar based on context, or ask the user if unclear.');
    buf.writeln(
        'When listing events, search all calendars whose prompt rules match the request.');
    if (_cachedEventsSummary != null) {
      buf.writeln('');
      buf.writeln(_cachedEventsSummary!);
    }
    return buf.toString();
  }

  /// Send a message with streaming response.
  /// [onSentence] is called with each complete sentence as it streams in,
  /// enabling TTS to start speaking before the full response arrives.
  Future<String> sendMessage(
    String userText, {
    void Function(String sentence)? onSentence,
  }) async {
    if (_client == null) {
      return 'Please set your Anthropic API key in settings.';
    }

    _history.add(InputMessage.user(userText));
    displayHistory.add(ChatMessage(role: 'user', text: userText));

    // Trim history, removing from front in pairs to maintain valid
    // user/assistant alternation and tool_use/tool_result pairing
    while (_history.length > _maxHistory * 2) {
      _history.removeRange(0, 2);
    }

    // Streaming tool-use loop
    while (true) {
      final accumulator = MessageStreamAccumulator();
      final sentenceBuffer = StringBuffer();
      bool hasToolUse = false;

      final stream = _client!.messages.createStream(_buildRequest());

      await for (final event in stream) {
        accumulator.add(event);

        // Detect tool use — stop emitting text to TTS for this round
        if (event is ContentBlockStartEvent &&
            event.contentBlock is ToolUseBlock) {
          hasToolUse = true;
        }

        // Stream text sentences to TTS as they arrive (final response only)
        if (!hasToolUse &&
            onSentence != null &&
            event is ContentBlockDeltaEvent &&
            event.delta is TextDelta) {
          sentenceBuffer.write((event.delta as TextDelta).text);
          _emitSentences(sentenceBuffer, onSentence);
        }
      }

      // Emit any remaining buffered text
      if (!hasToolUse && onSentence != null) {
        final remaining = sentenceBuffer.toString().trim();
        if (remaining.isNotEmpty) {
          onSentence(remaining);
        }
      }

      final response = accumulator.toMessage();

      // Check for tool use by content (not just stop reason) to handle
      // cases where maxTokens truncates a tool-use response
      final toolBlocks =
          response.content.whereType<ToolUseBlock>().toList();

      if (toolBlocks.isNotEmpty) {
        final results = await Future.wait(
          toolBlocks.map((b) => _executeTool(b.name, b.input)),
        );

        _history.add(InputMessage.assistantBlocks(
          response.content.map(_contentBlockToInput).toList(),
        ));

        final toolResults = <InputContentBlock>[];
        for (var i = 0; i < toolBlocks.length; i++) {
          toolResults.add(ToolResultInputBlock(
            toolUseId: toolBlocks[i].id,
            content: [ToolResultContent.text(results[i])],
          ));
        }

        _history.add(InputMessage(
          role: MessageRole.user,
          content: MessageContent.blocks(toolResults),
        ));

        continue;
      }

      // Final text response
      final text = response.text;
      _history.add(InputMessage.assistantBlocks(
        response.content.map(_contentBlockToInput).toList(),
      ));
      displayHistory.add(ChatMessage(role: 'assistant', text: text));
      return text;
    }
  }

  /// Extract complete sentences from the buffer and emit them via callback.
  void _emitSentences(
      StringBuffer buffer, void Function(String) onSentence) {
    while (true) {
      final text = buffer.toString();
      final match = RegExp(r'[.!?]\s+').firstMatch(text);
      if (match == null) break;

      final sentence = text.substring(0, match.start + 1).trim();
      if (sentence.isNotEmpty) {
        onSentence(sentence);
      }
      buffer.clear();
      buffer.write(text.substring(match.end));
    }
  }

  InputContentBlock _contentBlockToInput(ContentBlock block) {
    return switch (block) {
      TextBlock(:final text) => TextInputBlock(text),
      ToolUseBlock(:final id, :final name, :final input) =>
        ToolUseInputBlock(id: id, name: name, input: input),
      _ => TextInputBlock(''),
    };
  }

  MessageCreateRequest _buildRequest() {
    return MessageCreateRequest(
      model: _model,
      maxTokens: 1024,
      system: SystemPrompt.text(_buildSystemPrompt()),
      tools: allTools,
      messages: _history,
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

    // Fetch from all calendars in parallel
    final futures = calendarIds.map((calId) =>
        Services.calendar
            .listEvents(
              calendarId: calId,
              timeMin: startDate,
              timeMax: endDate,
            )
            .then((events) => events
                .map((event) {
                  final startDt =
                      (event.start?.dateTime ?? event.start?.date)
                          ?.toLocal();
                  final endDt =
                      (event.end?.dateTime ?? event.end?.date)?.toLocal();
                  return <String, dynamic>{
                    'calendar_id': calId,
                    'event_id': event.id,
                    'summary': event.summary,
                    'start': startDt?.toIso8601String(),
                    'start_day_of_week':
                        startDt != null ? _dayOfWeek(startDt) : null,
                    'end': endDt?.toIso8601String(),
                    'end_day_of_week':
                        endDt != null ? _dayOfWeek(endDt) : null,
                    'description': event.description,
                    'location': event.location,
                  };
                })
                .toList()));

    final results = await Future.wait(futures);
    final allEvents = results.expand((e) => e).toList();
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
          .map((c) =>
              {'id': c.id, 'name': c.name, 'description': c.description})
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
