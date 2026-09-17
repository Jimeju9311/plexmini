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

The server address lives at the top of `main.m`:

```objc
#define PLEX_SERVER   @"http://192.168.1.149:32400"
```

Change it to your own server before building.

## Build

```bash
./build.sh
```

If your Theos install isn't at `~/theos`:

```bash
THEOS=/opt/theos ./build.sh
```

This produces `PlexMini.app/` and a `PlexMini.app.tar.gz`.

## Install

```bash
DEVICE_PASS=your_password ./install.sh 192.168.1.42
```

The script copies the bundle, verifies by checksum that what landed on the device matches what you built, signs it with `ldid`, refreshes the icon cache and kills any running instance. On a first install you may need a manual `sbreload` for the icon to appear.

> **Note**: `scp -r` onto a directory that already exists **nests** the copy inside it (`PlexMini.app/PlexMini.app/…`) instead of replacing it, silently leaving the old binary in place and running. That's why the script removes the destination first and verifies the checksum — do the same if you deploy by hand.

---

## Architecture

Everything lives in a single `main.m` (~1500 lines), with no external dependencies:

| Component | Responsibility |
|---|---|
| `PlexClient` | HTTP client for the Plex API: PIN linking, JSON, images, subtitles |
| `LinkViewController` | Linking screen showing the `plex.tv/link` code |
| `PlexListViewController` | Library/show/season browsing (reused at every level) |
| `PlexDetailViewController` | Title detail: artwork, summary, play and subtitle buttons |
| `PlexPlayerViewController` | Player built on `AVPlayerLayer` with custom controls |
| `SubtitlePickerViewController` | Track selection and online search |
| `PlexPlayback` | Transcode URL construction |

`rt_shims.c` provides runtime symbols (`_Unwind_SjLj_*`) that the armv7s toolchain doesn't ship. For the same reason the code avoids the `%` operator on integers: `__modsi3` is missing.

### Why a custom player

`AVPlayerViewController` assumes it can seek freely within the stream. With HLS generated on the fly by Plex that isn't true: the server only produced segments from the point where transcoding started, so seeking outside that range returns data the player can't parse.

The correct approach — and what this app does — is to **restart the transcode at the new position** (`offset=`) and swap in a fresh `AVPlayerItem`, which means owning the scrub bar yourself.

---

## Notes on the Plex API

Behaviors verified against a real server that aren't documented anywhere, and that cost hours if you discover them by trial and error. They're in [`docs/PLEX_API.md`](docs/PLEX_API.md) — if you're building any Plex client, they'll probably save you an afternoon.

---

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Plex Inc. "Plex" is a trademark of Plex Inc.
