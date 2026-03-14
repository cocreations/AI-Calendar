import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;


class CalendarService {
  GoogleSignIn? _googleSignIn;
  gcal.CalendarApi? _calendarApi;
  GoogleSignInAccount? _currentUser;

  bool get isSignedIn => _currentUser != null;
  String? get userEmail => _currentUser?.email;

  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  GoogleSignIn get _signIn {
    _googleSignIn ??= GoogleSignIn(
      scopes: [gcal.CalendarApi.calendarScope],
      serverClientId: _webClientId.isNotEmpty ? _webClientId : null,
    );
    return _googleSignIn!;
  }

  Future<bool> signIn() async {
    try {
      _currentUser = await _signIn.signIn();
      if (_currentUser != null) {
        await _initCalendarApi();
        return true;
      }
      print('Google Sign-In: user was null (cancelled or no account selected)');
      return false;
    } catch (e, stack) {
      print('Google Sign-In error: $e');
      print('Stack: $stack');
      return false;
    }
  }

  Future<bool> signInSilently() async {
    try {
      _currentUser = await _signIn.signInSilently();
      if (_currentUser != null) {
        await _initCalendarApi();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _currentUser = null;
    _calendarApi = null;
  }

  Future<void> _initCalendarApi() async {
    final httpClient = await _signIn.authenticatedClient();
    if (httpClient != null) {
      _calendarApi = gcal.CalendarApi(httpClient);
    }
  }

  gcal.CalendarApi get _api {
    if (_calendarApi == null) throw StateError('Not signed in to Google');
    return _calendarApi!;
  }

  // List available calendars
  Future<List<gcal.CalendarListEntry>> listCalendars() async {
    final list = await _api.calendarList.list();
    return list.items ?? [];
  }

  // List events
  Future<List<gcal.Event>> listEvents({
    required String calendarId,
    required DateTime timeMin,
    required DateTime timeMax,
    String? query,
  }) async {
    final events = await _api.events.list(
      calendarId,
      timeMin: timeMin.toUtc(),
      timeMax: timeMax.toUtc(),
      singleEvents: true,
      orderBy: 'startTime',
      q: query,
    );
    return events.items ?? [];
  }

  // Create event
  Future<gcal.Event> createEvent({
    required String calendarId,
    required String summary,
    required DateTime start,
    required DateTime end,
    String? description,
    String? location,
  }) async {
    final event = gcal.Event()
      ..summary = summary
      ..start = (gcal.EventDateTime()..dateTime = start.toUtc())
      ..end = (gcal.EventDateTime()..dateTime = end.toUtc())
      ..description = description
      ..location = location;
    return await _api.events.insert(event, calendarId);
  }

  // Update event
  Future<gcal.Event> updateEvent({
    required String calendarId,
    required String eventId,
    String? summary,
    DateTime? start,
    DateTime? end,
    String? description,
    String? location,
  }) async {
    final existing = await _api.events.get(calendarId, eventId);
    if (summary != null) existing.summary = summary;
    if (start != null) {
      existing.start = gcal.EventDateTime()..dateTime = start.toUtc();
    }
    if (end != null) {
      existing.end = gcal.EventDateTime()..dateTime = end.toUtc();
    }
    if (description != null) existing.description = description;
    if (location != null) existing.location = location;
    return await _api.events.update(existing, calendarId, eventId);
  }

  // Delete event
  Future<void> deleteEvent({
    required String calendarId,
    required String eventId,
  }) async {
    await _api.events.delete(calendarId, eventId);
  }
}
