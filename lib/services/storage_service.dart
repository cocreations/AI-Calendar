import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/calendar_config.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  static const _keyApiKey = 'anthropic_api_key';
  static const _keyModel = 'claude_model';
  static const _keyCalendars = 'calendar_configs';

  static const defaultModel = 'claude-sonnet-4-20250514';

  static const modelOptions = [
    {'label': 'Smartest but expensive', 'id': 'claude-opus-4-20250514'},
    {'label': 'Basic', 'id': 'claude-sonnet-4-20250514'},
    {'label': 'Cheap but not quite as smart', 'id': 'claude-haiku-4-5-20251001'},
  ];

  // API Key
  Future<String?> getApiKey() => _storage.read(key: _keyApiKey);
  Future<void> setApiKey(String key) =>
      _storage.write(key: _keyApiKey, value: key);
  Future<void> deleteApiKey() => _storage.delete(key: _keyApiKey);

  // Model
  Future<String> getModel() async =>
      await _storage.read(key: _keyModel) ?? defaultModel;
  Future<void> setModel(String model) =>
      _storage.write(key: _keyModel, value: model);

  // Calendar configs
  Future<List<CalendarConfig>> getCalendarConfigs() async {
    final json = await _storage.read(key: _keyCalendars);
    if (json == null) return [];
    return CalendarConfig.listFromJson(json);
  }

  Future<void> setCalendarConfigs(List<CalendarConfig> configs) =>
      _storage.write(
          key: _keyCalendars, value: CalendarConfig.listToJson(configs));

  Future<void> addCalendarConfig(CalendarConfig config) async {
    final configs = await getCalendarConfigs();
    configs.add(config);
    await setCalendarConfigs(configs);
  }

  Future<void> removeCalendarConfig(String calendarId) async {
    final configs = await getCalendarConfigs();
    configs.removeWhere((c) => c.calendarId == calendarId);
    await setCalendarConfigs(configs);
  }

  Future<void> updateCalendarPrompt(String calendarId, String prompt) async {
    final configs = await getCalendarConfigs();
    final idx = configs.indexWhere((c) => c.calendarId == calendarId);
    if (idx != -1) {
      configs[idx] = configs[idx].copyWith(prompt: prompt);
      await setCalendarConfigs(configs);
    }
  }

  // Check if setup is complete
  Future<bool> isSetupComplete() async {
    final apiKey = await getApiKey();
    final calendars = await getCalendarConfigs();
    return apiKey != null && apiKey.isNotEmpty && calendars.isNotEmpty;
  }
}
