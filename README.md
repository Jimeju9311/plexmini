# PlexMini

A native Plex client for old 32-bit iPads and iPhones (iOS 9–10) running a jailbreak.

The official Plex app dropped iOS 10 years ago, which leaves a perfectly working iPad 4 with no way to watch your own Plex server. PlexMini is a minimal client written in plain Objective-C that does run there: it browses your libraries, plays through server-side transcoding, and handles subtitles.

Tested on an **iPad 4 (iPad3,4), iOS 10.3.3, h3lix jailbreak**, against **Plex Media Server 1.43**.

---

## What it does

- **PIN linking** with plex.tv (`plex.tv/link`) — the app never sees your password.
- **Library browsing** with thumbnails: movies, shows, seasons and episodes. It also handles the virtual "All episodes" node Plex returns for shows with flattened seasons.
- **Playback** through server-side HLS transcoding, so it works with HEVC, MKV, AC3 and everything else 2012 hardware can't decode on its own.
- **Accurate seeking** by dragging the scrub bar, plus ±10 s skips.
- **Subtitles**: toggle on/off, pick between tracks embedded in the file, and search/download new ones through your server's subtitle agents.
- **Custom player** with auto-hiding controls, built on `AVPlayerLayer` instead of `AVPlayerViewController` (see [Why a custom player](#why-a-custom-player)).

## What it doesn't do

Multi-user, Live TV/DVR, music, photos, Chromecast/AirPlay, offline downloads, scrubbing preview thumbnails (trickplay), resume where you left off, or autoplay of the next episode. This is a personal player, not a full Plex replacement.

---

## Requirements

**On the device:**
- A 32-bit iPhone/iPad running iOS 9.0–10.3.3 with a jailbreak (h3lix works well on 32-bit iOS 10.x).
- OpenSSH installed from Cydia/Sileo (for deployment).

**To build (from Linux or macOS):**
- [Theos](https://theos.dev/) with the iOS toolchain and the `iPhoneOS10.3.sdk`.
- `ldid` (ships with Theos) for ad-hoc signing.

**Server:**
- A Plex Media Server reachable on your local network.

---

## Configuration

The server address lives in `src/PlexConfig.h`:

```objc
#define PLEX_SERVER   @"http://ipaddress:port"
```

Change it to your own server before building. That's the only edit required.

If you'd rather not have your own address sitting in a tracked file — handy if you fork this — you can supply it at build time instead, and leave `PlexConfig.h` alone:

```bash
echo 'http://ipaddress:port' > server.local   # gitignored
./build.sh
```

or per-build: `PLEX_SERVER_URL=http://ipaddress:port ./build.sh`

## Build

```bash
./build.sh
```

If your Theos install isn't at `~/theos`:

```bash
THEOS=/opt/theos ./build.sh
```

This produces `PlexMini.app/` and a `PlexMini.app.tar.gz`.

---

## Install

### If you just want the app (no Theos, no compiler)

Grab `com.juan.plexmini_<version>_iphoneos-arm.deb` from the [Releases](https://github.com/Jimeju9311/plexmini/releases) page. It's a standard jailbreak package that installs into `/Applications`, and there are three ways to install it — no development tools needed:

**With Filza** (easiest, all on-device): copy the `.deb` to the iPad however you like (AirDrop, email, a web download), tap it in Filza, and choose *Install*.

**With Sileo or Cydia**: put the `.deb` somewhere the device can reach it, then open it with the package manager and confirm the install.

**Over SSH**, if you have OpenSSH from Cydia/Sileo:

```bash
scp com.juan.plexmini_*_iphoneos-arm.deb root@<device-ip>:/tmp/
ssh root@<device-ip> 'dpkg -i /tmp/com.juan.plexmini_*_iphoneos-arm.deb'
```

The default root password on a fresh jailbreak is `alpine` — **change it** before exposing SSH to anything.

**One caveat**: the server address is compiled into the binary, so a prebuilt package points at whatever server it was built against. Unless that happens to be yours, you'll need to [build it yourself](#build) after changing one line — which is really the intended path for anyone but me.

> If the icon doesn't appear on the home screen, respring the device (or run `uicache`). The package tries to refresh the icon cache on its own, but on iOS 10 `uicache` sometimes never returns, so it is deliberately fired off detached — the install always completes, and worst case you respring.

### If you build from source

```bash
DEVICE_PASS=your_password ./install.sh ipaddress
```

The script copies the bundle, verifies by checksum that what landed on the device matches what you built, signs it with `ldid`, refreshes the icon cache and kills any running instance.

> **Note**: `scp -r` onto a directory that already exists **nests** the copy inside it (`PlexMini.app/PlexMini.app/…`) instead of replacing it, silently leaving the old binary in place and running. That's why the script removes the destination first and verifies the checksum — do the same if you deploy by hand.

To build the installable package instead:

```bash
./package.sh
```

That produces the `.deb` described above.

### Why a `.deb` and not an `.ipa`

`.ipa` is the sideloading format for **non-jailbroken** devices, and it needs an Apple signing certificate — a free developer account gives you one that expires every 7 days, which means reinstalling the app weekly. Since this app targets jailbroken devices anyway, it installs into `/Applications` as a `.deb` with ad-hoc `ldid` signing: no Apple account, no expiry, and it behaves like any other package your device's package manager manages.

---

## Architecture

One class per file under `src/`, ~1600 lines total, with no external dependencies:

| File | Responsibility |
|---|---|
| `PlexConfig.h` | Server address and the `X-Plex-*` identity headers |
| `PlexClient` | HTTP client for the Plex API: PIN linking, JSON, images, subtitles |
| `PlexTheme` | Colors and the Core Graphics–drawn control icons |
| `LinkViewController` | Linking screen showing the `plex.tv/link` code |
| `PlexListViewController` | Library/show/season browsing (reused at every level) |
| `PlexCell` | Grid cell with async thumbnail loading |
| `PlexDetailViewController` | Title detail: artwork, summary, play and subtitle buttons |
| `PlexPlayerViewController` | Player built on `AVPlayerLayer` with custom controls |
| `PlexPlayback` | Transcode URL construction |
| `SubtitlePickerViewController` | Track selection and online search |
| `SubtitleSearchResultsViewController` | Results of an online subtitle search |
| `AppDelegate` | Window setup and the linked/not-linked decision at launch |

Icons are drawn in code with Core Graphics rather than shipped as image assets, which keeps the bundle to a single binary and renders crisply at any scale.

`rt_shims.c` provides runtime symbols (`_Unwind_SjLj_*`) that the armv7s toolchain doesn't ship. For the same reason the code avoids the `%` operator on integers: `__modsi3` is missing too.

### Why a custom player

`AVPlayerViewController` assumes it can seek freely within the stream. With HLS generated on the fly by Plex that isn't true: the server only produced segments from the point where transcoding started, so seeking outside that range returns data the player can't parse.

The correct approach — and what this app does — is to **restart the transcode at the new position** (`offset=`) and swap in a fresh `AVPlayerItem`, which means owning the scrub bar yourself.

---

## Notes on the Plex API

Behaviors verified against a real server that aren't documented anywhere, and that cost hours if you discover them by trial and error. They're in [`docs/PLEX_API.md`](docs/PLEX_API.md) — if you're building any Plex client, they'll probably save you an afternoon.

---

## License

PlexMini is released under the **MIT License** — the full text is in [LICENSE](LICENSE). In plain terms:

- **You can** use it, copy it, modify it, publish it, and distribute it, including commercially, without asking permission or paying anything.
- **You must** keep the copyright notice and the license text in any copy or substantial portion you distribute.
- **There is no warranty.** It's provided "as is". If it breaks something, that's on you — which is worth taking seriously here, since this is unsigned code running on a jailbroken device.

MIT was chosen over a copyleft license on purpose: most of the value in this repo is the [Plex API notes](docs/PLEX_API.md) and the working transcode/seek logic, and anyone should be able to lift those into their own client without their project inheriting license obligations.

### What the license does *not* cover

- **Plex itself.** "Plex" is a trademark of Plex, Inc. This project is not affiliated with, endorsed by, or supported by Plex, Inc. The name is used only to describe what the client talks to. No Plex source code, artwork, or assets are included or redistributed here — the app is an independent implementation against the server's HTTP API, using your own server and your own account.
- **Your media.** The app only plays content from a Plex server you already have access to. It provides no way to obtain content, and it bypasses nothing.
- **Subtitles** fetched by the online search come from your server's own subtitle agents and are subject to whatever terms those providers set.
