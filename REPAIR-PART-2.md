# TRMatrix — Repair Part 2, v9

This is a complete cumulative source project: all five earlier feature parts and Part 1 offline-text repair are included. Extract into a fresh folder; platform folders are already present. Do not regenerate them with flutter create.

## Included redesign
- Website-source colours with Sora/Manrope/JetBrains Mono fonts bundled for offline use (OFL licences included).
- Neutral full-screen canvas, circular/pill controls, less box-heavy Contacts, Calls, Profile/settings and Zone sections.
- Frosted mobile navigation with accent selection, hidden while the keyboard is open.
- Animated section entrance around the retained navigation shell; press/hover/keyboard-focus feedback, message entrance, microphone/send transitions and chat-info resizing. Shared animations respect Reduced motion.
- TRMatrix brand on the chat list, scrollable chat/contact/call filters, and New chat opens Contacts.
- Chat bubble widths follow the conversation pane, no heavy bubble shadows, subtle sent-message tint, stable hover-action space, 24-hour times.
- On narrow phones Video call, Wallpaper and Chat info are in More; voice calls and Zone stay visible. Stickers are available under Attach.
- Narrower tablet/desktop chat list and info panel leave more room for conversations.
- Contacts actions wrap on narrow phones. Call history is not reloaded just because appearance changed.
- Hives feed stays mounted while browsing My Hives. Avatar URL futures are retained across ordinary rebuilds.

## Checks completed here
- Dart source formatting/parser checks on changed files.
- 11 standalone offline persistence, account-isolation, concurrency and delivery regression checks passed.
- Standalone Dart analysis of offline store/tests: no issues.
- Source comparison and read-only review against the uploaded website and the v8 archive.

## Important limits
Full Flutter analysis, visual rendering, Windows/Android builds and signed-in end-to-end flows are NOT verified here. The official Flutter SDK download returned HTTP 404. Dart parser checks are not a substitute for Flutter analysis or device tests. This download is source, not a compiled APK/EXE.

## Test on your devices
Flutter 3.29+ is required for the existing modern colour APIs.

```sh
flutter pub get
flutter analyze
flutter run -d windows
```
For Android use flutter devices, then flutter run -d <your-device-id>.

Check:
1. Sign-in and sign-up on phone/Windows; all fields and long button labels fit.
2. Chat headers, long messages, reply preview, attachments and composer at narrow phone/tablet/desktop widths.
3. Keyboard Tab/Enter/Space on controls; Reduced motion; dark/light/AMOLED, accent, text size and compact mode.
4. Draft and chat scroll retention when changing sections; restart offline and repeat the Part 1 reconnect/duplicate-delivery checks.
5. Feed → My Hives → Feed retains loaded posts and scroll position.
6. Existing media, calls and Watch together with real devices; these flows were not newly validated here.

Send flutter analyze/build errors and screenshots of screens needing further changes.

## Remaining phases
Part 3 will address missing website features: pin/mute/archive controls, presence, message formatting, session lock, avatar cropping, animated wallpapers, device settings and a richer upload queue. Offline media and non-chat disk caching remain incomplete. Hives retention in this part is memory retention, not restart/offline feed caching. Zone voice effects, spatial audio and recording are not included in this visual repair.
