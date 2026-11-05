# Version 1.0.0 validation

Validated on the development Mac on November 5, 2026.

- All 19 automated tests pass: 14 core tests and 5 application-state tests.
- A real local UDP receiver verifies three exact 102-byte magic packets and the configured destination port.
- A real local TCP listener verifies reachable and closed-port results.
- Import tests cover delimiter variants, quoting, UTF-8 BOM, header aliases, headerless names, invalid values, duplicate MACs, port limits, malformed records, formula-safe export, and the 10,000-row boundary.
- Persistence tests check atomic round trips, duplicate rejection, preserved identities during update, and protection of corrupt files against overwrites.
- Application tests check import skip/update behavior, atomic failure, selection across filters, deletion state, and network-free demo waking.
- Native UI review exercised import preview with one valid row, one invalid IP and one duplicate MAC; committing the valid row; selecting six computers; and per-computer demo batch results. First-launch onboarding was visually checked.
- Adversarial review corrected selection/detail mismatch, eager batch rendering, repeated inventory scans during import, stale wake results after edits, and hidden error detail.
- Universal release binary contains arm64 and x86_64 slices, both targeting macOS 14.0. The Intel slice was compiled, not executed on Intel hardware.
- The app icon was checked at 1024, 32 and 16 pixels.

Packet transmission tests do not prove that a particular physical computer will wake. No user's real computer was powered on during development. Wake-on-LAN depends on target firmware, adapter configuration and network routing. Online status checks the configured TCP service, not operating-system uptime.

Run `swift test` to reproduce automated checks. `scripts/release.sh` verifies the signed bundle, Apple's notarization ticket, and Gatekeeper acceptance before creating the distribution archive.
