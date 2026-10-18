# QuickShareMac tests

Build the Debug app, then run the standalone test suites:

```sh
Scripts/build-development.sh
Tests/run-ui-smoke-tests.sh
Tests/run-sending-integration-tests.sh
Tests/run-shared-identity-tests.sh
Tests/run-update-checker-tests.sh
swift Scripts/generate-app-icon.swift --check
```

The UI suite uses a fake sending service: it does not discover or contact devices.
It covers Send/Receive navigation, file/folder selection and drag-and-drop, Share
menu handoff for files, folders, and links, including merging the multiple open
events LaunchServices can send for one handoff, approval,
progress, cancellation, retry isolation, background completion, history, and native
menu bar behavior (menu attachment, appearance defaults, actions, live transfer rows,
pending-request review, icon progress, cancellation, and live state).
All selections, including a single file, folder, or shared link, use a native selectable
table with icons, full-path/URL tooltips, alternating row colors, and a persistent
legacy scrollbar in a dedicated scroll area capped at five rows. Checks cover reaching
the last filename, keeping the card/tab/window height fixed as more items are added,
shrinking and resetting short replacement lists, file/folder compression, replacement,
rejected selections, one-row sizing for single items, replacing files with links, and clearing on shutdown.
Item-action checks exercise actual right-click row targeting, Open/Reveal callbacks
without launching apps or Finder, missing-file/launch-failure handling, shared-link
menus, right-aligned remove buttons, last-item clearing, source-file preservation,
stale-menu/button safety, and active-transfer editing guards. Drop checks cover
ordered additive selection on either tab, deduplication without rediscovery,
invalid additions and file/link isolation, and preserving selection/scroll position.
Folder edits during enumeration and deferred compression verify cancellation and
isolation from stale callbacks. Light/dark snapshots cover the table appearance.
Remove All checks cover placement beside the count, empty-list visibility, discovery
shutdown, source-file and history preservation, active-transfer guards, shared links,
and cancellation of pending folder enumeration/compression without late restoration.
The folder-compression setting is checked for default-off behavior, persistence,
Settings callbacks, live overlay changes, and applying only to new selections.
Uncompressed folders are checked for nested paths, hidden and zero-byte files,
mixed selections, same-named roots and sanitized directory collisions, unreadable
children, skipped symbolic links, empty-folder errors, retries that gather files
again, and replacement/shutdown isolation from late enumeration callbacks.
Scroll checks verify that approval controls remain reachable in a constrained
window, and that a new approval request scrolls back to the
top. Incoming-transfer checks cover the per-row **Cancel** action: only active
receives offer it, clicking it identifies the transfer, it stays reachable in a
constrained window, and finished or canceled rows replace it with their status,
Dismiss, and Show in Finder as appropriate.
Compact Receive checks ensure the status heading and device-specific
instructions appear only once, the instruction row fits at narrow widths in both
appearances, and enabling receiving and reviewing incoming requests remain usable.
The upper-right pin button is tested for direct one-click Always on top control,
normal/floating window levels, toggle state, blue highlighting, tooltips, tab-switch
persistence, restored state, and leaving other windows unaffected. Header checks cover Settings
wiring, the unchanged brand artwork in a compact upper-left header, smaller title
typography, long device-name truncation without overlapping actions, Send/Receive tab
order and icons, soft backgrounds, blue primary actions, reduced card corner radii,
less-rounded native buttons/tabs, and light/dark card colors. Settings appearance
checks cover the same compact unchanged-logo header, soft background/cards,
reduced corner radii, icon navigation, blue Save/Check for Updates actions, and a
fixed developer footer across all pages. Narrow/default window sizes and both
appearances are checked, including long folder-name truncation, visible folder
actions, scrollable General content, and header/footer stability during scrolling.
The developer credit footer is checked on both the Receive and Send tabs for
centering, bottom placement, resizing, and staying outside cards/scrolling content.
Auto-fit checks cover compact initial size, tab and selection changes, keeping the
title bar anchored, bounded filename-list height, screen limits with scrolling
fallback, incoming approval controls, shrinking after history clears, and stable
repeated layout. Settings reset checks cover targeted preference restoration,
preserving unrelated data and remembered devices, confirmation/cancellation, and
refreshing the default controls without modifying real user preferences.
Drag checks cover the window-wide overlay on both tabs, filename/count previews,
copy-only cursor feedback, resizing/dark appearance, folder accept-with-compression,
rejected links/missing files, drop-time revalidation, active-transfer changes during
a hover, cleanup on exit/cancel/window removal, and recipient selection without
automatic sending.
Folder compression is exercised end-to-end with `ditto`: a temporary folder tree is
compressed, the ZIP is checked for its name, PK signature, and included parent
folder, a missing folder must fail with a named error, and the Send flow must present
and transfer a ZIP (not the folder) after the spinner phase. The rate estimator is
checked for baseline, exact, throttled, smoothed, and restarted samples plus
speed/ETA wording. Incoming-request presentation is checked for the active-app,
background-with-notifications, and no-notifications fallbacks, and the notification
copy is verified to name the device and point at the PIN check. History retry is
covered for folders: **Send again** recompresses the original folder instead of
pointing at deleted temporary ZIPs.
It also checks the read-only device-name card: the current advertised name with
an edit action, editing only revealing the system/custom choice and input,
Save/Cancel appearing only once something changed, Done closing an untouched
editor, prefilled custom input, refresh isolation, friendly inline validation,
save confirmation/failure handling, and collapsing back to read-only after save
or cancel; read-only visibility details,
availability dropdowns, timer replacement/expiry, and deadlines passed during sleep.
Settings update-frequency selection and status-menu update actions, busy states, and update availability are
also covered, without making update requests or opening a browser.
Settings checks also cover General/Updates/About navigation, grouped controls,
preserving the selected page on refresh, About credits/version, resizing,
scrollable validation messages, and dark appearance. The received-files save
folder is covered through the Settings callbacks, folder-name display, hidden
reset state, and default restoration, plus bookmark persistence, missing-folder
rejection, and the Downloads fallback in the store. The Receive tab's save-folder
footer and the Open Received Files button in the tab row are checked for
placement and wiring.
Manual-update result dialogs are exercised with both closed and open Settings
windows: they must stay standalone, preserve Settings visibility/navigation,
deduplicate repeated presentation, and open release URLs only on explicit action.

The integration suite exercises the real encrypted file-transfer protocol on
`127.0.0.1`. Received files are written into a disposable temporary directory,
never Downloads. It checks multi-chunk transfers, empty files, filename collisions,
rejection, cancellation, and unexpected disconnection.
It verifies that outgoing handshakes carry the configured local device name.
Recorded decrypted introductions and file payload headers verify consistent
relative folder paths, including zero-byte EOF payloads. Absolute/traversal paths
are rejected and path components are sanitized. The loopback receiver saves loose
files; actual Android folder reconstruction must be checked on a phone.

The shared-identity suite creates disposable sandboxed, ad-hoc-signed host and
extension probes. It uses an isolated preference domain to verify that the host
can save a name, the extension can read it, and the extension cannot overwrite it.
It does not modify the app's real device-name preference or network permissions.

The update-checker suite needs only the Swift compiler, not a prior app build.
It uses an isolated preferences domain and URLProtocol fixtures, never contacting
GitHub. It checks semantic version comparison, stable-release filtering, trusted
release links, caching, daily/weekly/calendar-month scheduling, Never/manual checks,
checkbox-preference migration, overlapping requests, no-release
responses, offline/server errors, rate-limit backoff, and shutdown cancellation.

Set `UI_SNAPSHOT_DIR` to an existing directory to save optional UI snapshots.
Real Android-device discovery and QR handshakes still require device testing.

The icon check verifies all ten AppIcon resolutions have the expected dimensions,
centered artwork, and transparent margins matching the macOS Dock footprint.
Regenerate them from the unchanged full-bleed brand image with
`swift Scripts/generate-app-icon.swift`.

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
