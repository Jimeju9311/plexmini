# Notes on the Plex transcoding API

Behaviors verified empirically against **Plex Media Server 1.43** while building PlexMini, by reading the server log (`Plex Media Server.log`) whenever something didn't add up. None of these are in the official documentation or in `python-plexapi`, and several are counter-intuitive.

---

## 1. `start.m3u8` requires a prior `decision` with the same `session`

Calling `/video/:/transcode/universal/start.m3u8` directly returns **400**, and the log says:

```
Denying access due to session lacking decision for transcode of key /library/metadata/551
```

You have to request `/video/:/transcode/universal/decision` first, with **exactly the same parameters** and the same `session=`, and only then `start.m3u8`.

---

## 2. `AVPlayer.currentTime` is already an absolute position

When you start a transcode with `offset=953`, the HLS segments keep the original file's timestamps. The player does not start counting from zero: `currentTime` starts at ~953.

Adding the offset again to work out "where are we" doubles the position:

```
base=953   player.currentTime=966   base+played=1919   ← wrong
```

**The absolute position is `currentTime` as-is.** Don't add the offset you started from.

---

## 3. `fastSeek=1` lands on a keyframe, not where you asked

`fastSeek=1` makes the transcoder start at the nearest available keyframe. On files with widely spaced keyframes that can land several minutes past the requested point, seemingly at random.

Use `fastSeek=0` when you need precision: it takes a second or two longer to start, but lands exactly.

---

## 4. `subtitleStreamID` on the transcode URL is ignored

Even if you send it on both `decision` and `start.m3u8`, Plex resolves the subtitle through its **own auto-selection** based on the account's language preferences. The log shows it picking the same stream regardless of what was requested:

```
Selecting best audio stream for part ID 833 (language: )
Audio Stream: 5070, Subtitle Stream: 5515     ← 5515, even though 5072 was requested
```

What that auto-selection *does* honor is the file's persisted default subtitle:

```
PUT /library/parts/{partId}?subtitleStreamID={streamId}&allParts=1
```

Set that first; use `subtitleStreamID=0` to turn subtitles off.

---

## 5. Changing subtitles requires a brand new session

Reusing the same `session=` only applies time changes. The subtitle stays frozen as it was when the session was created.

To change it: `stop` the old session → new `session` (fresh UUID) → `decision` + `start.m3u8`.

```
GET /video/:/transcode/universal/stop?session={oldSessionId}
```

---

## 6. Browsing: `key` vs `ratingKey`

- **Library sections** (`/library/sections`): `key` is a plain number, you build `/library/sections/{key}/all`.
- **Shows and seasons**: `key` already contains a ready-to-use absolute path, e.g. `/library/metadata/555/allLeaves` for the virtual *"All episodes"* node of a show with flattened seasons — and **that node has no `ratingKey` of its own**.

Rule of thumb: if `key` starts with `/`, use it as-is; otherwise build the path from `ratingKey`.

Also, **`ratingKey` sometimes arrives as a JSON number and sometimes as a string**. Validating it with `isKindOfClass:[NSString class]` silently discards valid entries.

---

## 7. Session hygiene

Every open transcode session keeps an ffmpeg process alive on the server. If the client walks away without saying anything, it lingers there burning CPU. Always call:

```
GET /video/:/transcode/universal/stop?session={sessionId}
```

when closing the player and before rotating to a new session.
