# Push notifications

You get a push like `brian placed 🦆🎨🐛` when someone else places emoji on a canvas
you share. Placements are batched so a burst arrives as one notification, and it
is delivered passively — into the notification list, without a sound or waking
the screen.

## Setup (one time, by hand)

Nothing here is in the repo — the signing key is a secret, and `deploy.sh` only
rsyncs git-tracked files, so the droplet's copies survive deploys the same way
`user_tokens.json` does.

1. In the Apple Developer portal, enable the Push Notifications capability for
   the App ID `com.maxbickers.goose-art`, then create an APNs auth key and
   download the `.p8`.
2. Put the key on the droplet at `/opt/goose-art/apns_key.p8`, alongside
   `/opt/goose-art/apns_config.json`:

```json
{
  "keyPath": "apns_key.p8",
  "keyId": "ABCD123456",
  "teamId": "TEAM123456",
  "bundleId": "com.maxbickers.goose-art"
}
```

The same key signs both APNs environments, and which one a push goes to is a
property of the *user*: `use_sandbox_notifications` in `server/users.py`. It has
to match how that user's app was built — sandbox for a build run from Xcode,
production for TestFlight or the App Store — because a device token is only valid
in the environment the app registered with, and a mismatch is dropped silently
rather than reported as an error. The `dev user 1`/`dev user 2` accounts are the
sandbox ones; `max` and `brian` are production.

Without `apns_config.json` the server runs with notifications disabled and logs
`push notifications disabled: no apns_config.json` at startup, so a local server
needs no credentials.

## How it works

**Delivery — `server/apple_notifications.py`.** Everything APNs, and nothing else.

- `DeviceNotificationTokenRegistry` maps user id to APNs device tokens, persisted to
  `device_notification_tokens.json`. A device belongs to one user at a time: registering it
  moves it, so logging in as someone else on a shared phone stops delivering the
  previous user's notifications.
- `send_push(user_id:, body:)` sends to one user's devices, through the APNs
  environment that user is configured for, and drops tokens APNs rejects
  permanently. Sends are `passive`, because the batch is coalesced and so can
  land seconds after the user already watched the placement appear: an
  interruption would be for news they have had for a while.

**Everything else — `server/canvas_notifications.py`.** What to say and when to
say it. `placed_emojis` compares the canvas before and after a message and reports
the placements that appeared, and `flush_placements` formats the batch and sends
it to each recipient.

`Coalescer[Key, Event]` also lives here rather than beside the APNs code, because
batching is a decision about *this* notification, not something pushes need in
general. It groups events sharing a key into one flush, anchoring the window at
the *first* event of a batch rather than extending it, so a steady stream still
delivers on a bounded delay instead of being held back indefinitely.

**Wiring — `server/main.py`.** `POST /deviceNotificationToken` registers a device, and
`canvas_handler` feeds new placements into the coalescer.

Comparing states rather than reading the actions keeps
`DistributedStateMachineServer` untouched, and means the cases that shouldn't
notify fall out on their own rather than each needing a rule: an emoji that was
only moved keeps its id, one that was placed and dragged off the canvas in the
same message never lands in the after state, and actions a reconnecting client
resends change nothing at all. Your own placements don't notify you either.

The one wrinkle is ordering: new emoji are reported in the order they ended up in
the canvas's z-order, not the order they were placed. That is only visible when a
single message carries several placements *and* re-upserts one of them, which
means an offline client reconnecting.

**iOS.** `AuthenticationService` asks iOS to register when a session starts and
posts the token in `receivedDeviceNotificationToken`, reading the auth token back out of
`TokenStore` rather than holding it. `PushNotificationDelegate` in
`GooseArtApp.swift` is only the seam UIKit requires: it hands the token to the
authentication service and suppresses banners while the app is foregrounded,
because the canvas already shows an arriving placement live.

## Adding a second kind of notification

Write a module next to `canvas_notifications.py` holding whatever that kind needs
— the text it produces, and a `Coalescer` if it should batch — then call
`send_push` and trigger it from wherever the event happens.
`apple_notifications.py` shouldn't need to change: it only knows how to get a
string to a user's devices. There is deliberately no routing or preference system
until something actually needs one.

## Testing delivery

The simulator's `simctl push` will exercise presentation, but a real end-to-end
send needs a device (or an Apple Silicon simulator, which supports real APNs
sandbox pushes) so that a genuine device token reaches `/deviceNotificationToken`.
