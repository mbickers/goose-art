# Deployment

The server and the app ship separately, and neither one waits on the other.

## Server

```sh
server/deploy.sh
```

It transfers git-tracked files only, so commit first — an uncommitted change
will not go out — and so anything untracked on the droplet survives, which is
what keeps the APNs key and the user token store in place across deploys.

## App

1. **Push to `main`.** Xcode Cloud starts a build when the push touches `ios/`.
2. **Distribute the build in App Store Connect** once it finishes processing. A
   green build is not a delivered one.
3. **Tell users to update.** TestFlight does not install new builds on its own,
   so anything the new build needs from the server has to keep working for the
   old one until everyone has updated.

The start condition only matches `ios/`, and `goose-art.xcodeproj/` sits at the
repo root, outside it. A push that only edits the project file — a version bump,
a build setting, a new package dependency — starts nothing, which looks exactly
like a slow queue. Start those builds by hand in App Store Connect.

Which APNs environment a user gets is a property of that user rather than the
build, so a user moving between an Xcode build and TestFlight needs
`use_sandbox_notifications` changed to match. See
[notifications.md](notifications.md).
