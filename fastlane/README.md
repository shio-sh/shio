fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios setup

```sh
[bundle exec] fastlane ios setup
```

One-time: create the iOS app record in App Store Connect

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build the iPhone/iPad app and upload to TestFlight

----


## Mac

### mac release

```sh
[bundle exec] fastlane mac release
```

Build, Developer-ID-sign, and notarize the Mac app → build/mac (DIRECT download, not the App Store)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
