# Push notifications

You get a push like `brian placed 🦆🎨🐛` when someone else places emoji on a canvas
you share. Placements are batched so a burst arrives as one notification.

## Setup (one time, by hand)

Nothing here is in the repo — the signing key is a secret, and `deploy.sh` only
rsyncs git-tracked files, so the droplet's copies survive deploys the same way
`static_data.json` does.

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
  "bundleId": "com.maxbickers.goose-art",
  "useSandbox": false
}
```

`useSandbox` has to match how the app was built: `true` for a build run from
Xcode, `false` for TestFlight or the App Store. A mismatch is dropped silently
rather than reported as an error, so it is worth double checking.

Without `apns_config.json` the server runs with notifications disabled and logs
`push notifications disabled: no apns_config.json` at startup, so a local server
needs no credentials.

## How it works

**Generic layer — `server/notifications.py`.** Knows nothing about canvases.

- `DeviceTokenRegistry` maps user id to APNs device tokens, persisted to
  `device_tokens.json`. A device belongs to one user at a time: registering it
  moves it, so logging in as someone else on a shared phone stops delivering the
  previous user's notifications.
- `send_push(user_ids:, body:)` fans out to those users' devices and drops tokens
  APNs rejects permanently.
- `Coalescer[Key, Event]` batches events sharing a key into one flush. The window
  is anchored at the *first* event of a batch rather than extended by later ones,
  so a steady stream still delivers on a bounded delay instead of being held back
  indefinitely.

**Producer — `server/canvas_notifications.py`.** The only part that knows what an
emoji is. `placed_emojis` compares the canvas before and after a message and
reports the placements that appeared; `flush_placements` formats the batch and
sends it.

**Wiring — `server/main.py`.** `POST /deviceToken` registers a device, and
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

**iOS — `ios/PushNotificationService.swift`.** The device token and the signed-in
session arrive independently and in either order, so both are held until there is
enough to register. Banners are suppressed while the app is foregrounded, since
the canvas already shows an arriving placement live.

## Adding a second kind of notification

Write a new producer module next to `canvas_notifications.py`: a key type, a flush
that calls `send_push`, and a `Coalescer` if that kind should batch. Then call
`add` from wherever the event happens. Nothing in the generic layer needs to
change, and there is deliberately no routing or preference system until something
actually needs one.

## Testing delivery

The simulator's `simctl push` will exercise presentation, but a real end-to-end
send needs a device (or an Apple Silicon simulator, which supports real APNs
sandbox pushes) so that a genuine device token reaches `/deviceToken`.
