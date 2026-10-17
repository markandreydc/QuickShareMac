# Sending and UI tests

Build the Debug app, then run both standalone test suites:

```sh
Scripts/build-development.sh
Tests/run-ui-smoke-tests.sh
Tests/run-sending-integration-tests.sh
Tests/run-shared-identity-tests.sh
```

The UI suite uses a fake sending service: it does not discover or contact devices.
It covers Send/Receive navigation, file-only selection and drag-and-drop, Share
extension link handling, approval,
progress, cancellation, retry isolation, background completion, history, and native
menu bar behavior (menu attachment, appearance defaults, actions, and live state).
It also checks device-name validation/persistence, read-only visibility details,
availability dropdowns, timer replacement/expiry, and deadlines passed during sleep.

The integration suite exercises the real encrypted file-transfer protocol on
`127.0.0.1`. Received files are written into a disposable temporary directory,
never Downloads. It checks multi-chunk transfers, empty files, filename collisions,
rejection, cancellation, and unexpected disconnection.
It verifies that outgoing handshakes carry the configured local device name.

The shared-identity suite creates disposable sandboxed, ad-hoc-signed host and
extension probes. It uses an isolated preference domain to verify that the host
can save a name, the extension can read it, and the extension cannot overwrite it.
It does not modify the app's real device-name preference or network permissions.

Set `UI_SNAPSHOT_DIR` to an existing directory to save optional UI snapshots.
Real Android-device discovery and QR handshakes still require device testing.

## Signing and local-network permission

The Debug targets use complete ad-hoc bundle signing for local development. Keep
signing enabled; `CODE_SIGNING_ALLOWED=NO` produces an app with an invalid bundle
signature and missing signed entitlements. The build script verifies the app and
its embedded extension/libraries before reporting success.

Ad-hoc signing is not notarization or a stable certificate-based identity. For
consistent permission identity across rebuilds, select an Apple Development
certificate and your team in Xcode. No certificate is installed automatically.
If macOS denies local networking despite its Settings toggle being enabled,
fully quit and reopen the verified build, then recheck its Local Network entry.
The app reports policy denial explicitly and provides an Open Network Settings
action; it never resets or grants system permissions itself.
