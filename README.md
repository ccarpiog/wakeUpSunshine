# Wake Up Sunshine

<img src="docs/icon.png" width="128" alt="A power-button sun rising above the horizon">

A native macOS Wake-on-LAN app for a whole room of computers. Inspired by the clear split-view layout of [MagicPing](https://magicping.net/en/), with original visuals and a workflow built around bulk import and batch waking.

Requires **macOS 14 or later**. The release app supports Apple Silicon and Intel Macs.

## What it does

- Add computers by name, IPv4 address, and MAC address.
- Import CSV, TSV, or semicolon-separated lists, or paste rows directly. Review valid rows and errors before saving.
- Skip existing MAC addresses or update their settings when importing.
- Organize computers into groups, search the list, and select multiple computers to wake together.
- Reorder computers with the up/down controls beside each row, or right-click and choose Move Up / Move Down. The order is saved automatically.
- Send real Wake-on-LAN magic packets, with per-computer broadcast address and UDP port.
- Check a configurable TCP service to see whether a computer is reachable.
- Review per-computer wake results and export the inventory as CSV.
- Keep the inventory locally, without an account, backend, or analytics.

This version focuses on macOS and Wake-on-LAN. It does not include iCloud synchronization, remote shutdown, or companion iPhone/Watch/TV apps.

## Start using it

Download the [signed release ZIP](https://github.com/ccarpiog/wakeUpSunshine/releases/latest), unzip it, and move **Wake Up Sunshine.app** to Applications. Open the app, then add a computer or import a list. Allow local network access when macOS asks.

Clicking the red window-close button quits the app completely. Computer records and their order are saved as you make changes and are available when you reopen it.

Enable Wake-on-LAN in each target computer's BIOS/UEFI and network adapter settings. An Ethernet connection is generally needed; wake support depends on the hardware, operating system, and sleep/shutdown state.

Choose computers using the list checkboxes, then wake the selection. A successful send means the operating system accepted the UDP packets. It does **not** prove that the remote computer woke up. **Online** means the configured TCP probe port accepted a connection; a sleeping computer and an awake computer blocking that port can both appear unreachable.

**Select all** selects every saved computer, including computers hidden by a search or group filter. When a filter hides selected computers, the sidebar shows how many are outside the current view. **Clear** removes the selection.

Use the up/down arrows on the right of a computer row to reorder the list. You can also right-click a row and choose **Move Up** or **Move Down**. When a search or group filter is active, reordering rearranges the visible computers while hidden computers keep their positions. New computers are appended; editing or updating an existing computer preserves its position. CSV exports use the saved list order.

The default probe port is **22**. Change it to a service that is actually listening on that computer—for example SSH (22), SMB (445), RDP (3389), or your configured Sunshine service port. The probe does not sign in or issue commands.

The default wake destination is **255.255.255.255**, UDP **9**. This is a local network broadcast. If necessary, set the correct subnet broadcast for your network; the app does not assume every network uses a `/24` subnet. Routers and most VPNs do not forward broadcasts automatically. Configure remote-network routing explicitly if you need to wake computers across subnets.

## Import format

Start with [the example CSV](docs/computers-example.csv). Replace its example addresses with your own.

```csv
name,ip,mac,group,broadcast,wake_port,probe_port
Gaming PC,192.168.1.42,02:11:22:33:44:01,Home,255.255.255.255,9,47990
Office Mac,192.168.1.17,02:11:22:33:44:02,Office,255.255.255.255,9,22
"NAS, media",192.168.1.10,02:11:22:33:44:03,Home,255.255.255.255,9,445
```

`name`, `ip`, and `mac` are required. The optional fields default to group `General`, broadcast `255.255.255.255`, wake port `9`, and probe port `22`.

The importer accepts comma, tab, or semicolon delimiters; quoted fields; UTF-8 byte-order marks; and headerless rows in `name,ip,mac,group` order. MAC addresses are normalized before duplicate detection. Duplicate MACs within the incoming file and invalid rows appear in the preview. Existing computers are matched by MAC, with an explicit skip/update choice. Review the preview's valid count and issues before importing.

Files are limited to 10 MB and 10,000 computers.

## Export and local storage

Use CSV export as a portable inventory backup. Computer status and activity are runtime observations and are not part of the inventory export. To keep spreadsheet software from treating names or groups as formulas, export prefixes an apostrophe when either field starts with `=`, `+`, `-`, or `@` (including after leading whitespace). Reimporting that CSV preserves the protective apostrophe; ordinary names and groups round-trip unchanged. The saved local inventory itself is not altered by export.

The inventory is saved atomically at `~/Library/Application Support/WakeUpSunshine/computers.json`. If that file cannot be read, the app prevents accidental overwrites. Activity is kept for the current session, up to 300 entries. Status checks run when the app opens and periodically while it is running; each probe has a timeout and large inventories are checked with bounded concurrency.

## Build and test

Install Xcode with its command-line tools. The app uses SwiftUI, AppKit, and system networking APIs; it has no third-party package dependencies.

```sh
swift test
scripts/build.sh
open 'build/Wake Up Sunshine.app'
```

`build.sh` builds both `arm64` and `x86_64`, combines them into a universal executable, generates the original icon at all macOS icon sizes, and creates an ad-hoc signed app bundle. This development signature is not a notarized distribution signature.

For quicker local iteration:

```sh
scripts/build.sh --debug --native
open 'build/Wake Up Sunshine.app' --args --demo
```

`--demo` uses a separate sample inventory for visual review. It does not populate the normal inventory.

See [validation notes](docs/VALIDATION.md) for the release checks and their limits.

Open `Package.swift` in Xcode to work on the project. The GitHub workflow runs tests and uploads a universal development build; official distribution requires the separate signing step.

## Sign and notarize

After tests and visual review, build a Release app and run:

```sh
scripts/build.sh
scripts/release.sh
```

The release script follows the owner's local `SIGN_AND_NOTARIZE.md` runbook. It uses an installed Developer ID Application identity and the existing `AC_NOTARY_PROFILE` keychain profile. `CRED_ROOT`, `NOTARY_PROFILE`, and `SIGNING_IDENTITY` can be overridden through environment variables. API identifiers are read from the original credential directory at runtime; private keys and certificates are never copied into this repository.

The script signs with hardened runtime and a secure timestamp, submits the app to Apple, staples the accepted ticket, and verifies Gatekeeper acceptance. It then creates the distribution ZIP **after** stapling, with a SHA-256 checksum:

```text
build/WakeUpSunshine-1.1.1-macOS.zip
build/WakeUpSunshine-1.1.1-macOS.zip.sha256
build/notarization.json
```

Release logs stay in the ignored `build/release-logs/` directory. If notarization fails, the script stops and fetches Apple's diagnostic log when a submission ID is available. Do not modify the app bundle after signing and stapling.

## License

[MIT](LICENSE). This is an independent project and is not affiliated with MagicPing.


## Developer ID certificate renewal (November 2026)

macOS releases now select the G2 certificate by its exact SHA-1 fingerprint,
`D90FF6C655C831F11CC50642E4EF8675905EAF79` (team `CXVKS8ZNCD`, expires December 8, 2027).
The old certificate may remain in the keychain; it is never a fallback for a new release.
The selection policy is in `scripts/lib/developer-id.sh`.

For a subsequent renewal, set `DEVELOPER_ID_SHA1` to the complete new fingerprint,
install its matching private key and certificate, and update any Developer ID provisioning
profiles to contain that certificate. The scripts reject missing, malformed, wrong-team,
or wrong-type identities. Update the default fingerprint and expiry after verification.
The legacy `Certificates.p12` backup predates G2; restore only a backup verified to contain
the selected identity. Do not commit private keys or certificate backups.

Run `bash scripts/test-developer-id.sh` for identity-selection and output-certificate checks.

`SIGNING_IDENTITY` remains an alias when `DEVELOPER_ID_SHA1` is unset, but must now be a full fingerprint.
