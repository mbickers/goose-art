# Deployment

The server and the app ship separately; neither waits on the other.

## Server

```sh
server/deploy.sh
```

Only git-tracked files are transferred, so an uncommitted change will not go out,
and anything untracked on the droplet survives — which is what keeps the APNs key
and the user token store in place across deploys.

Saved canvases are untracked too, so a change to the format they are written in
has to be migrated on the droplet by hand after the deploy that changed it.

## App

1. **Push to `main`.** Xcode Cloud starts a build when the push touches `ios/`.
2. **Distribute the build in App Store Connect** once it finishes processing. A
   green build is not a delivered one.
3. **Announce the update.** TestFlight does not install new builds on its own, so
   anything the new build needs from the server has to keep working for the old
   one until every install has updated.

The start condition matches only `ios/`, and `goose-art.xcodeproj/` sits at the
repo root, outside it. A push that edits only the project file — a version bump,
a build setting, a new package dependency — starts nothing, which is
indistinguishable from a slow queue. Start those builds by hand in App Store
Connect.

The APNs environment is a property of the user rather than the build, so a user
moving between an Xcode build and TestFlight needs `use_sandbox_notifications`
changed to match. See [notifications.md](notifications.md).
