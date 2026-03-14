# AI Calendar

A voice-first calendar app powered by Claude. Speak commands like "What do I have today?" or "Schedule lunch with Bob at noon tomorrow" and the AI handles the rest.

Built with Flutter. No backend server — runs entirely on-device with direct API calls to Google Calendar and Anthropic.

## How It Works

```
Your voice → Device speech-to-text → Claude (with calendar tools) → Device text-to-speech
```

Claude uses tool calling to read/write your Google Calendar and search a local contacts database. You talk, it acts, it talks back.

## Features

- Voice-controlled calendar management (create, update, delete, list events)
- Multi-calendar support with customizable AI routing rules
- Local contacts/people memory ("Remember that Sarah is from the riverschool")
- Choose your Claude model (Opus / Sonnet / Haiku)
- Conversation history for context-aware follow-ups

## Prerequisites

- Flutter SDK (3.38+)
- Android SDK (for Android builds)
- Xcode (for iOS builds)
- An Anthropic API key ([console.anthropic.com](https://console.anthropic.com))
- A Google Cloud project (free — setup below)

## Google Cloud Setup

This is the only non-trivial setup step. You need your own Google Cloud project so the app can access Google Calendar on behalf of users.

### 1. Create a project

Go to [console.cloud.google.com/projectcreate](https://console.cloud.google.com/projectcreate) and create a new project (any name).

### 2. Enable the Calendar API

Go to [console.cloud.google.com/apis/library/calendar-json.googleapis.com](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) and click **Enable**.

### 3. Configure the OAuth consent screen

Go to [console.cloud.google.com/apis/credentials/consent](https://console.cloud.google.com/apis/credentials/consent).

- Choose **External** user type
- Fill in App name ("AI Calendar"), your email for support/developer contact
- On the Scopes step, add: `https://www.googleapis.com/auth/calendar`
- On the Test users step, add your own Google account email
- Save and continue through remaining steps

> While in "Testing" mode, only the test users you list can sign in. When you're ready for wider use, publish the app to move out of testing mode.

### 4. Create OAuth credentials

Go to [console.cloud.google.com/apis/credentials](https://console.cloud.google.com/apis/credentials) and click **Create Credentials > OAuth client ID**.

You need to create **two** client IDs (three if building for iOS):

#### a) Web application (required — even for mobile)

- Application type: **Web application**
- Name: anything (e.g. "AI Calendar Web Client")
- No redirect URIs needed
- Click Create

> Google Sign-In on Android uses this behind the scenes. Without it, sign-in silently fails with no useful error message.

#### b) Android

- Application type: **Android**
- Package name: `au.com.cocreations.ai_calendar`
- SHA-1 fingerprint: get yours by running:
  ```bash
  # Debug key (for development)
  keytool -list -v -keystore ~/.android/debug.keystore \
    -alias androiddebugkey -storepass android 2>/dev/null | grep "SHA1:"

  # Release key (if you have one)
  keytool -list -v -keystore /path/to/your/keystore \
    -alias your_alias -storepass your_password 2>/dev/null | grep "SHA1:"
  ```
- Click Create

Note down the **Client ID** from the Web application credential you created in step 4a — you'll need it to run the app (see Build & Run below).

#### c) iOS (only if building for iOS)

- Application type: **iOS**
- Bundle ID: `au.com.cocreations.aiCalendar`
- Click Create
- Note the **Client ID** and the **iOS URL scheme** (reversed client ID) from the created credential

Then configure iOS locally (this file is gitignored — never committed):

```bash
cp ios/Runner/GoogleAuth.xcconfig.example ios/Runner/GoogleAuth.xcconfig
```

Edit `ios/Runner/GoogleAuth.xcconfig` with your values:

```
GOOGLE_IOS_CLIENT_ID=123456789-abcdef.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID=com.googleusercontent.apps.123456789-abcdef
```

## Build & Run

You must pass your **Web application** OAuth client ID (from step 4a) via `--dart-define`:

```bash
# Install dependencies
flutter pub get

# Run on connected device
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com

# Build release APK
flutter build apk --release --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

> Tip: to avoid typing the client ID every time, create a local (gitignored) file like `run.sh`:
> ```bash
> #!/bin/bash
> flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=123456789-abc.apps.googleusercontent.com
> ```

### Release signing (Android)

To sign release builds, create `android/key.properties` (gitignored):

```properties
storePassword=your_password
keyPassword=your_password
keyAlias=your_alias
storeFile=/path/to/your/keystore
```

Generate a keystore if you don't have one:

```bash
keytool -genkey -v -keystore my-release-key.jks \
  -alias my_alias -keyalg RSA -keysize 2048 -validity 10000
```

## Using the App

1. **Setup** (first run only): Sign in with Google, enter your Anthropic API key, pick your calendars
2. **Talk**: Tap the mic and speak naturally
3. **Settings**: Change AI model, manage calendars and their routing rules, view saved contacts

### Example voice commands

- "What do I have today?"
- "Schedule a meeting with Bob tomorrow at 2pm"
- "What's Stacey doing this weekend?" (searches only Stacey's calendar if you've set a routing rule)
- "Move my 2pm meeting to 3pm"
- "Cancel my meeting with Bob"
- "Remember that Sarah is the woman from the riverschool with brown hair"
- "Who was that person from the riverschool?"

### Multi-calendar routing

Each linked calendar has a prompt rule that tells the AI when to search it:

- First calendar defaults to: *"Always search this calendar"*
- Additional calendars get rules like: *"Only search if the request mentions Stacey"*

The AI reads these rules and decides which calendars to query for each request.

## Project Structure

```
lib/
├── main.dart                       # Entry point
├── app.dart                        # App widget + initial routing
├── models/
│   └── calendar_config.dart        # Calendar ID + name + AI routing prompt
├── services/
│   ├── services.dart               # Service locator
│   ├── storage_service.dart        # Secure storage (API key, model, calendar configs)
│   ├── calendar_service.dart       # Google Sign-In + Calendar v3 API
│   ├── contacts_service.dart       # Local SQLite contacts database
│   ├── speech_service.dart         # Speech-to-text + text-to-speech
│   └── ai_service.dart             # Claude client + tool execution loop
├── screens/
│   ├── setup_screen.dart           # Onboarding (Google auth, API key, calendar picker)
│   ├── voice_screen.dart           # Main voice interaction UI
│   └── settings_screen.dart        # Model, calendars, contacts, API key
└── tools/
    └── calendar_tools.dart         # Claude tool definitions
```

## Credentials & Security

**No credentials are stored in source code.**

| Credential | Where it lives | How it's configured |
|---|---|---|
| Google OAuth client IDs | Google Cloud Console | Matched by package name + SHA-1 (Android) or xcconfig file (iOS, gitignored) |
| Anthropic API key | Device secure storage | User enters during setup, stored in iOS Keychain / Android Keystore |
| Release signing key | `android/key.properties` | Gitignored, each developer creates their own |
| iOS Google client ID | `ios/Runner/GoogleAuth.xcconfig` | Gitignored, each developer creates their own from the `.example` template |

## License

MIT
