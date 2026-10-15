# TRMatrix repair — Part 1 (full cumulative source)

This archive includes the previous five feature parts and the first repair pass.
It is source code, not a prebuilt APK or Windows executable.

## Changed in this repair
- Already opened conversations and chat-list summaries read from an encrypted device cache immediately, then refresh in the background.
- Text and replies are saved before the composer clears. Pending text survives restarting the app and retries every 12 seconds while signed in and the app is open.
- Retries retain the same UUID and check for an already-delivered server row before inserting; a failed request does not discard text.
- Main sections retain their mounted pages when switched through the navigation bar/rail. Search, filters, scroll and an active conversation stay in memory while the app remains open.
- Conversation drafts stay in memory across chat navigation (not across an app restart).
- New message rows have a short fade/slide, disabled by reduced-motion settings.
- Native encrypted data uses private app-support files, with AES-GCM and keys in the platform secure store. This is local cache encryption, not new end-to-end encryption.
- Android corrections included: desktop-only media-kit native dependencies, guarded initialization, desugaring 2.1.4, existing 2 GB Gradle / 1 GB Kotlin limits retained, backup disabled for the encrypted cache/key pair.

## Run and test
Extract into a NEW folder. Keep the previous project as a backup; do not overwrite platform changes you made locally.

```
flutter clean
flutter pub get
flutter analyze
dart test_offline.dart
flutter run -d windows
# For Android, use flutter devices, then flutter run -d <your-device-id>
```

Use a current stable Flutter SDK. Linux secure storage also needs
`sudo apt install libsecret-1-dev libjsoncpp-dev` (plus the existing media/Flutter build libraries).
macOS secure-storage keychain groups are included. Web secure storage requires localhost or HTTPS and browser storage quotas still apply.

### On-device acceptance checks
1. Sign in online. Open several conversations to populate saved messages.
2. Switch between Messages, Calls, Hives and Contacts; return to Messages. Confirm the same active chat/filter/scroll remains.
3. Turn internet off. Reopen an already viewed chat. Confirm saved text appears without waiting on a network spinner.
4. Send two texts offline. They should have a pending clock and remain visible.
5. Close/reopen the app while still offline, using its retained session. Reopen the chat and confirm both texts remain.
6. Restore internet with the app open; confirm each text appears once on the other person's app/website and the pending clocks clear.
7. Sign out and sign in as a different account. Previously cached messages must not appear.

## What is NOT finished
- This is NOT full Telegram/WhatsApp offline parity. Only chat summaries, fetched text/message metadata, chat details and outgoing text/replies persist in this pass.
- Only the latest 200 server messages per opened conversation are downloaded. Earlier history/pagination and full background prefetch are still pending.
- Media files, downloaded avatars, voice notes, attachments and wallpapers are not cached for offline playback, and outgoing media is not yet queued.
- Contacts, Hives and Calls retain their page state in the current session, but do not yet have durable offline caches after restart. A fresh page load may still need internet.
- Creating chats, reactions, edits/deletes, admin operations, live calls and Zones remain online actions. Read-receipt retries are not yet durable.
- You must have signed in previously; a new login requires internet. Sign-out deletes the account's local cache and UNSENT text, so reconnect/send pending text before signing out.
- Delivery retry works while the app is open, not as a guaranteed OS background service.
- The complete website-matched visual redesign is repair Part 2. Website missing-feature parity is repair Part 3. Neither is claimed finished here.
- The current cache serializes one encrypted account file; very large retained histories still need a database-backed cache in a later pass.

## Validation performed here
- 11 deterministic Dart checks passed: disk-backed restart, pending-text persistence, retry/deduplication, account separation/deletion, concurrent writes, failed disk saves and account switching during delivery.
- The offline store and test file passed Dart static analysis; changed Dart files passed syntax formatting.
- Full Flutter package resolution was blocked by a TLS failure reaching pub.dev; the Flutter SDK archive was unavailable from the attempted download hosts.
- Full `flutter analyze`, APK/Windows compilation, platform secure-storage encryption and the signed-in website/device delivery flow are NOT verified here. Please run the above acceptance checks and send the first failing output.
