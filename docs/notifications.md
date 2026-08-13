# Push notifications

A push such as `brian placed 🦆🎨🐛` is delivered when another user places emoji on
a shared canvas. It names every placement the recipient has not seen, not only
what just landed. Each push replaces the previous one, so a burst is a single
notification whose body grows. Delivery is passive: the notification lands in the
list without a sound or waking the screen.

## Setup (one time, by hand)

None of this is in the repo — the signing key is a secret, and `deploy.sh`
rsyncs only git-tracked files, so the droplet's copies survive deploys the same
way `user_tokens.json` does.

1. In the Apple Developer portal, enable the Push Notifications capability for
   the App ID `com.maxbickers.goose-art`, create an APNs auth key, and download
   the `.p8`.
2. Place the key on the droplet at `/opt/goose-art/apns_key.p8`, alongside
   `/opt/goose-art/apns_config.json`:

```json
{
  "keyPath": "apns_key.p8",
  "keyId": "ABCD123456",
  "teamId": "TEAM123456",
  "bundleId": "com.maxbickers.goose-art"
}
```

One key signs both APNs environments. Which one a push goes to is a property of
the *user*: `use_sandbox_notifications` in `server/users.py`. It has to match how
that user's app was built — sandbox for a build run from Xcode, production for
TestFlight or the App Store — because a device token is valid only in the
environment the app registered with, and a mismatch is dropped silently rather
than reported as an error. `dev user 1` and `dev user 2` are the sandbox
accounts; `max` and `brian` are production.

Without `apns_config.json` the server runs with notifications disabled and logs
`push notifications disabled: no apns_config.json` at startup, so a local server
needs no credentials.

## How it works

**Delivery — `server/apple_notifications.py`.** Everything APNs, and nothing else.

- `DeviceNotificationTokenRegistry` maps user id to APNs device tokens, persisted to
  `device_notification_tokens.json`. A device belongs to one user at a time: registering it
  moves it, so logging in as someone else on a shared phone stops delivery of the
  previous user's notifications.
- `send_push(user_id:, body:, collapse_id:)` sends to one user's devices through
  the APNs environment that user is configured for, and drops tokens APNs rejects
  permanently. The collapse id is what makes a send *replace* the recipient's
  previous notification rather than stack on it, so it is required rather than
  optional: every kind of notification has to decide what it supersedes. Sends
  are `passive`, landing in the notification list without a sound or waking the
  screen — a placement is worth seeing but not worth interrupting for.

**Everything else — `server/canvas_notifications.py`.** What to say and when to
say it. `placed_emojis` compares the canvas before and after a message and reports
the placements that appeared, and `PlacementNotifier` decides who hears about them.

There is no timer. A placement notifies immediately, and the push names every
emoji that recipient has not seen from that placer — not just the ones that
arrived — under a collapse id of `placer:recipient`. A burst is therefore one
notification whose body grows as it goes, which is what a coalescing delay used
to buy, without the notification arriving after the emoji have already been
watched appearing.

*Seen* means holding a live canvas connection. A connected recipient is served
the canvas as it changes, so nothing placed during a connection is unseen at all,
and connecting clears whatever had piled up — the canvas handed over on subscribe
shows all of it at once. Connections are counted rather than flagged, because one
user can have several devices and one of them going away doesn't mean that user
stopped looking.

Emptying the canvas drops what is unseen on it as well, since the emoji a push
would name are gone. Both ways of emptying it count — the nightly clear, and a
user taking the last placement off — the same two the saved-canvas snapshot
treats alike.

This leans on a connection meaning someone is actually looking, which is why the
client hangs up on backgrounding (below). It is still a proxy: a device that
loses the network without closing cleanly stays "connected" until the socket
does, and placements in that window are never notified.

**Wiring — `server/main.py`.** `POST /deviceNotificationToken` registers a device, and
`canvas_handler` reports connects, disconnects, new placements, and an emptied
canvas to the notifier, as does the nightly clear.

Comparing states rather than reading the actions keeps
`DistributedStateMachineServer` untouched, and makes the cases that shouldn't
notify fall out on their own rather than each needing a rule: an emoji that was
only moved keeps its id, one that was placed and dragged off the canvas in the
same message never lands in the after state, and actions a reconnecting client
resends change nothing at all. Self-placements do not notify either.

The one wrinkle is ordering: new emoji are reported in the canvas's z-order, not
the order they were placed. That is visible only when a single message carries
several placements *and* re-upserts one of them, which means an offline client
reconnecting.

**iOS.** `AuthenticationService` asks iOS to register when a session starts and
posts the token in `receivedDeviceNotificationToken`, reading the auth token back out of
`SessionStore` rather than holding it. `PushNotificationDelegate` in
`GooseArtApp.swift` is only the seam UIKit requires: it hands the token to the
authentication service, suppresses banners while the app is foregrounded because
the canvas already shows an arriving placement live, and clears delivered
notifications when the app becomes active, since the visible canvas has overtaken
them.

The canvas connection follows the scene phase rather than the session:
`enteredBackground` hangs up and `enteredForeground` reconnects, driven by
`onChange(of: scenePhase)`. That is what makes the server's "connected means it
was seen" reading true — a suspended app left holding its socket would otherwise
silently absorb placements no one saw. `.inactive` is deliberately not a hang-up:
it is what the app switcher and a pulled-down notification center look like, with
the canvas still on screen behind them.

## Adding a second kind of notification

Write a module next to `canvas_notifications.py` holding whatever that kind needs
— the text it produces, and whatever it tracks to decide the text is worth
sending — then call `send_push` and trigger it from wherever the event happens.
`apple_notifications.py` should not need to change: it only knows how to get a
string to a user's devices. There is deliberately no routing or preference system
until something actually needs one.

## Testing delivery

`simctl push` in the simulator exercises presentation. An end-to-end send needs a
device — or an Apple Silicon simulator, which supports real APNs sandbox pushes —
so that a genuine device token reaches `/deviceNotificationToken`.
