import 'dart:convert';

class CalendarConfig {
  final String calendarId;
  final String name;
  final String prompt;

  const CalendarConfig({
    required this.calendarId,
    required this.name,
    required this.prompt,
  });

  Map<String, dynamic> toJson() => {
        'calendarId': calendarId,
        'name': name,
        'prompt': prompt,
      };

  factory CalendarConfig.fromJson(Map<String, dynamic> json) => CalendarConfig(
        calendarId: json['calendarId'] as String,
        name: json['name'] as String,
        prompt: json['prompt'] as String,
      );

  CalendarConfig copyWith({String? calendarId, String? name, String? prompt}) =>
      CalendarConfig(
        calendarId: calendarId ?? this.calendarId,
        name: name ?? this.name,
        prompt: prompt ?? this.prompt,
      );

  static List<CalendarConfig> listFromJson(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => CalendarConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<CalendarConfig> configs) =>
      jsonEncode(configs.map((c) => c.toJson()).toList());
}
