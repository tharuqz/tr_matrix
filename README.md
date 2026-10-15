# TR MATRIX — Flutter app (Part 1 of 5)

Connects to the same backend as trmatrix.top, so your existing accounts and chats work.

## Run it
1. Install Flutter 3.24+ (https://docs.flutter.dev/get-started/install).
2. Open a terminal in this folder and run:
   ```
   flutter create . --project-name trmatrix_app --platforms=android,ios,windows,macos,web
   flutter pub get
   flutter run -d windows      # or: -d chrome, -d android, -d macos
   ```
   `flutter create .` only adds the platform folders; it keeps the code in `lib/`.
3. Android: add `<uses-permission android:name="android.permission.INTERNET"/>` to
   `android/app/src/main/AndroidManifest.xml` if it isn't there.
   macOS: in `macos/Runner/*.entitlements`, add `com.apple.security.network.client` = true.

## What's in Part 1
- Obsidian Matrix design (colours, Sora/Manrope/JetBrains Mono fonts, glass panels, glow, radii)
- Dark / AMOLED / Light themes + accent colours
- Username + PIN sign-in and sign-up (same accounts as the website)
- Adaptive layout: < 600px mobile, 600–900 tablet, > 900 desktop
  - Desktop: icon rail + chat list + active chat + right info panel (≥ 1200px), hover states,
    tooltips, visible scrollbars, Ctrl/Cmd+1–5 to switch sections, Enter to send, Esc to close
  - Mobile: floating pill bottom bar, full-screen chats, swipe-right to go back,
    swipe a message to reply, info as a draggable bottom sheet, safe areas
- Messages: chat list (search, All/Unread/Groups/Archived, unread badges, live updates),
  chat view (live messages, replies, read receipts, day dividers)
- Contacts: friends, requests (accept/decline/cancel), search & add, "Message" opens a chat

## Coming next
- Part 2: files/photos, voice notes, stickers, reactions, edit/delete, message action sheet, chat themes & wallpapers, groups
- Part 3: voice/video calls (desktop overlay + mini picture-in-picture, mobile full-screen), call history
- Part 4: Hives feed, full profile & settings, devices, app lock
- Part 5: Admin/Security, Zones (watch together, music), notifications

## Part 2 — what's new
- Send photos, videos and any file (up to 50 MB) from the + button, or drag files onto a chat on computers.
- Tap a photo to open it full screen; tap a file to open/download it.
- Voice notes: tap the mic (shown when the message box is empty), then send or discard. Works on phone, computer and Chrome.
- Stickers: smiley button → "+" turns any picture into a sticker. Stickers are saved on this device, and the website shows them as stickers too.
- Long-press (phone) or right-click / "…" (computer) a message: react, reply, copy, edit, delete for everyone.
- Groups: "New group" button above the chat list; tap a group's name for members, add/remove, rename, leave.
- Chat wallpaper: wallpaper button in the chat header (presets or your own picture, shared with everyone in the chat).

### One-time setup after `flutter pub get`
**Android** — in `android/app/src/main/AndroidManifest.xml` add inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```
**iOS** — in `ios/Runner/Info.plist` add:
```xml
<key>NSMicrophoneUsageDescription</key><string>Record voice notes</string>
<key>NSPhotoLibraryUsageDescription</key><string>Send photos</string>
```
**macOS** — in both `macos/Runner/*.entitlements` add `com.apple.security.device.audio-input`, `com.apple.security.network.client` and `com.apple.security.files.user-selected.read-only` set to `true`, and the same microphone text in `macos/Runner/Info.plist`.
**Linux** — voice notes need `sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev` (audio playback) and `parecord`/PulseAudio (recording).

---

## Part 3 — Calls

What's new:
- Voice and video calls from any chat (header buttons or the chat info panel), and call-back from the **Calls** tab.
- 1-to-1 calls use the same signals as the website, so **app ↔ website** calls work both ways.
- **Group calls** (new): everyone in the group gets an invite and joins; each person connects directly to every other (best with up to ~6 people). Group calls are **app ↔ app only** — the website doesn't understand group calls yet.
- **Ringtone** for incoming calls, ringing tone while you're calling, and vibration on phones. (Browsers may stay silent until you've clicked the page once — browser rule.)
- **Screen sharing** during any call: Windows/macOS show a screen/window picker; Chrome uses its own picker; Android shows a "Sharing your screen" notification. Not available on iPhone/iPad (Apple requires a separate extension).
- Incoming call card on top of every screen, full call screen with mute / camera / switch camera / speaker / share / hang up, and a minimized draggable mini window.
- Call history written to the same `call_logs` table as the website.

Run `flutter pub get` after updating.

### Permissions to add

**Android** — `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```
and inside `<application>`:
```xml
<service android:name="de.julianassmann.flutter_background.IsolateHolderService"
    android:exported="false" android:foregroundServiceType="mediaProjection"/>
```
Set `minSdkVersion 23` in `android/app/build.gradle`.

**iOS** — `ios/Runner/Info.plist`: `NSCameraUsageDescription` and `NSMicrophoneUsageDescription` (e.g. "Needed for calls"). Set platform to iOS 13 in `ios/Podfile`.

**macOS** — in both `macos/Runner/*.entitlements` add `com.apple.security.device.camera` = true (plus the microphone/network ones from Part 2), and `NSCameraUsageDescription` in `macos/Runner/Info.plist`. Set macOS 10.15 in `macos/Podfile`.

**Windows** — nothing extra.

### Known limits
- Calls only ring while the app is open (background push for the app comes in Part 5).
- Group calls with many people use more data, since each person sends video to everyone.

---

## Part 4 — Hives, profile & settings

Run `flutter pub get` after updating. No new permissions are needed (photo picking reuses Part 2's file permissions).

What's new:
- **Hives tab**
  - Community feed: share posts with photos, videos and files (up to 10, 50 MB each), choose who sees them (friends / everyone / chosen friends), choose how long they stay up (1 hour to 1 month; admins can pick "Forever"), turn comments on/off. Emoji reactions, comments, edit and delete. Respects the website's "posting paused" switch. Updates live.
  - My Hives: your groups with search, create a new Hive, jump to its chat.
  - Hive activities (same as the website): time capsules that unlock later, decision trails with votes, reasons and a final outcome, shared missions (claim / done / release tasks) and quiet catch-ups.
- **Profile tab / avatar button**
  - Change profile picture, display name and About, with the same name colours and moving effects as the website (shown in both places).
  - Settings with search: theme (Dark / AMOLED / Light / follow system), accent colour, font size, compact mode, reduced motion, hide notification previews, about.
  - Settings are remembered on each device.
- Profile pictures stored privately by the website now show correctly everywhere.

---

## Part 5 — Zones, Security (admin) & notifications

Run `flutter pub get` after updating.

### What's new
- **Zones** — tap the headphones button at the top of any chat.
  - Always-on voice room for that chat, shared with website users (same room).
  - Mute / deafen, see who's in and who's muted, emoji reactions, a Zone-only text chat (not saved).
  - Share your screen (computers) and watch others' shared screens.
  - Music together: paste a YouTube link, queue tracks, play/pause, skip. Plays in step for everyone on Android, iPhone, Mac and web; on Windows/Linux the track opens in YouTube.
- **Security tab (admins only)**
  - Site controls: maintenance mode and community posting lock.
  - Members: search, activate / suspend / ban, delete account (frees the username).
  - Flagged reports: mark reviewed or dismiss.
  - Maintenance mode now locks the app for non-admins too, live.
- **Notifications**
  - While the app is open (Windows, Mac, Linux, Android, iPhone): pop-ups for new messages in chats you're not looking at. Muted chats stay quiet. "Hide notification previews" in settings is respected.
  - Phones with the app closed: messages, friend requests, Hive posts and **incoming calls** arrive through your website's existing push sender. Calling from the app now also rings the other person's phone.
  - Signing out removes the phone from your notification list.

### Phone notifications setup (one time)
Your website already sends pushes through Firebase. The app must use the **same Firebase project**:
1. In the Firebase console, open the project your website uses → Project settings → add an **Android app** with your app's package name (in `android/app/build.gradle`, `applicationId`) and download `google-services.json` into `android/app/`.
2. Add an **iOS app** too if you build for iPhone and put `GoogleService-Info.plist` in `ios/Runner/` (also upload an APNs key in Firebase → Cloud Messaging).
3. Easiest: install the FlutterFire tool and run `flutterfire configure` in the project folder — it does steps 1–2 for you.
4. Android extra permissions in `AndroidManifest.xml` (inside `<manifest>`):
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
```
   and in `android/app/build.gradle` set `minSdkVersion 23`, `compileSdk 34`, and enable desugaring:
```gradle
compileOptions { coreLibraryDesugaringEnabled true }
dependencies { coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.0.4' }
```
Without Firebase files the app still works — you just won't get alerts while it's closed.

### Zones music on Android/iPhone
The YouTube player needs internet permission (already added in Part 1). On iOS add to `Info.plist`: `io.flutter.embedded_views_preview` = `YES`.

### Known limits
- Zones voice effects, spatial audio, recording and "Watch together" video from the website are not in the app yet; app users still hear and talk with everyone.
- Windows/Linux get pop-ups only while the app is running (no push when closed).

## Watch together on Windows / Linux (in-app player)
Windows and Linux now play Zone videos inside the app (media_kit + youtube_explode_dart), synced with everyone.
- Run `flutter pub get`.
- Windows: nothing extra needed.
- Linux: `sudo apt install libmpv-dev mpv` (Fedora: `sudo dnf install mpv-libs-devel`).
- Optional backup: install `yt-dlp` — if a video can't be looked up, the player lets mpv/yt-dlp fetch it.
- If YouTube changes something and videos stop loading, run `flutter pub upgrade youtube_explode_dart`.
