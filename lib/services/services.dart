import 'storage_service.dart';
import 'calendar_service.dart';
import 'contacts_service.dart';
import 'speech_service.dart';
import 'ai_service.dart';

class Services {
  static final storage = StorageService();
  static final calendar = CalendarService();
  static final contacts = ContactsService();
  static final speech = SpeechService();
  static late AiService ai;

  static Future<void> init() async {
    await speech.init();
    final apiKey = await storage.getApiKey();
    final model = await storage.getModel();
    final calendars = await storage.getCalendarConfigs();
    ai = AiService(
      apiKey: apiKey ?? '',
      model: model,
      calendarConfigs: calendars,
    );
  }

  static Future<void> reinitAi() async {
    final apiKey = await storage.getApiKey();
    final model = await storage.getModel();
    final calendars = await storage.getCalendarConfigs();
    ai = AiService(
      apiKey: apiKey ?? '',
      model: model,
      calendarConfigs: calendars,
    );
  }
}
