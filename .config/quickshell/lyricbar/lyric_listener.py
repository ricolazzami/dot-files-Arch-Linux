#!/usr/bin/env python3
"""
lyric_listener.py
Helper script for Quickshell Floating LyricBar widget.
Monitors MPRIS players (Spotify, Amberol, MPD, VLC, Chrome, Firefox, Cider, YouTube Music, etc.),
synchronizes timestamps from .lrc lyrics (local search & LRCLIB API),
and streams the active line to stdout in real-time as JSON.
Includes --demo mode for testing animations and auto-resizing.
"""

import sys
import os
import re
import json
import time
import bisect
import urllib.request
import urllib.parse
from pathlib import Path

# Local lyric search paths
LYRIC_CACHE_DIR = Path.home() / ".cache" / "lyrics"
LOCAL_LYRIC_DIRS = [
    Path.home() / ".lyrics",
    Path.home() / ".cache" / "lyrics",
    Path.home() / ".config" / "quickshell" / "lyrics",
    Path.home() / "Music" / "lyrics",
    Path(__file__).parent / "lyrics",
]

# Ensure cache directory exists
LYRIC_CACHE_DIR.mkdir(parents=True, exist_ok=True)


def clean_track_metadata(raw_title: str, raw_artist: str = "", album: str = "", url: str = ""):
    """
    Cleans and normalizes track metadata, especially from web browsers (Chrome, Firefox, Chromium,
    Brave, Zen) playing YouTube Music, YouTube, Soundcloud, Bandcamp, etc.
    Extracts real artist & title from complex video titles (e.g. 'Artist - Song (Official Video)').
    Strips browser suffixes, Topic tags, VEVO suffixes, and video tags.
    """
    if not raw_title:
        return "", ""

    title = raw_title.strip()
    artist = raw_artist.strip() if raw_artist else ""

    # 1. Strip web platform & browser suffixes from title iteratively
    # Delimiters can be hyphen, en-dash, em-dash, pipe, bullet, middle dot
    browser_suffixes = [
        r"\s*[-–—|•·]\s*YouTube\s+Music(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*YouTube(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*(?:Google\s+)?Chrome(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*Chromium(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*(?:Mozilla\s+)?Firefox(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*Brave(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*Zen\s+Browser(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*Soundcloud(?:\s+.*)?$",
        r"\s*[-–—|•·]\s*Bandcamp(?:\s+.*)?$",
    ]
    while True:
        changed = False
        for s in browser_suffixes:
            new_title = re.sub(s, "", title, flags=re.IGNORECASE).strip()
            if new_title != title:
                title = new_title
                changed = True
        if not changed:
            break

    # Strip web platform prefixes (e.g. 'YouTube Music - Song', 'YouTube - Song')
    browser_prefixes = [
        r"^YouTube\s+Music\s*[-–—|•·]\s*",
        r"^YouTube\s*[-–—|•·]\s*",
    ]
    for p in browser_prefixes:
        title = re.sub(p, "", title, flags=re.IGNORECASE).strip()

    # 2. Clean generic or browser artist names
    generic_artists = {
        "youtube", "youtube music", "google chrome", "chrome",
        "firefox", "mozilla firefox", "chromium", "brave", "zen",
        "zen browser", "unknown artist", "various artists", "web browser"
    }
    if artist.lower().strip() in generic_artists:
        artist = ""

    # Filter out generic / placeholder titles (e.g. when browser tab is just 'YouTube Music')
    generic_titles = {
        "youtube music", "youtube", "google chrome", "chrome",
        "chromium", "firefox", "mozilla firefox", "brave",
        "zen browser", "zen", "web browser", "new tab",
        "untitled", "home", "search", "music", "audio", "video",
        "unknown"
    }
    if title.lower().strip() in generic_titles and (not artist or artist.lower().strip() in generic_artists):
        return "", ""

    # 3. Clean auto-generated Topic / VEVO artist suffixes
    if artist:
        artist = re.sub(r"\s+-\s+Topic$", "", artist, flags=re.IGNORECASE)
        artist = re.sub(r"(?<=[a-zA-Z0-9])VEVO$", "", artist, flags=re.IGNORECASE)

    # 4. Remove common video junk tags in titles
    video_junk = [
        r"\(Official\s+(?:Music\s+)?Video\)",
        r"\[Official\s+(?:Music\s+)?Video\]",
        r"\(Official\s+Audio\)",
        r"\[Official\s+Audio\]",
        r"\(Official\s+Lyric\s+Video\)",
        r"\[Official\s+Lyric\s+Video\]",
        r"\(Official\s+Visualizer\)",
        r"\[Official\s+Visualizer\]",
        r"\(Lyric\s+Video\)",
        r"\[Lyric\s+Video\]",
        r"\(Lyrics\)",
        r"\[Lyrics\]",
        r"\(Visualizer\)",
        r"\[Visualizer\]",
        r"\(Audio\)",
        r"\[Audio\]",
        r"\(Video\)",
        r"\[Video\]",
        r"\(M/?V\)",
        r"\[M/?V\]",
        r"\((?:HD|4K|HQ|UHD)\)",
        r"\[(?:HD|4K|HQ|UHD)\]",
        r"\(Color\s+Coded\s+Lyrics\)",
        r"\(slowed\s*\+\s*reverb\)",
        r"\(sped\s+up\)",
        r"\(speed\s+up\)",
        r"\(Audio\s*/\s*Lyrics\)",
        r"\(Full\s+Audio\)",
        r"\[Full\s+Audio\]",
        r"\(Performance\s+Video\)",
        r"\[Performance\s+Video\]",
        r"\(Clip\s+Officiel\)",
        r"\[Clip\s+Officiel\]",
        r"\(Video\s+Oficial\)",
        r"\[Video\s+Oficial\]",
        r"\(Official\)",
        r"\[Official\]",
    ]
    for junk in video_junk:
        title = re.sub(junk, "", title, flags=re.IGNORECASE)

    # 5. Check if title contains compound delimiters
    # First check bullet points e.g. 'Song • Artist' (common on YouTube Music)
    split_bullet = re.search(r"\s+[•·]\s+", title)
    if split_bullet:
        cand1 = title[:split_bullet.start()].strip()
        cand2 = title[split_bullet.end():].strip()
        if not artist:
            # On YouTube Music tab titles, format is 'Title • Artist'
            title, artist = cand1, cand2
        elif cand2.lower() in artist.lower() or artist.lower() in cand2.lower():
            title = cand1
            artist = cand2
        elif cand1.lower() in artist.lower() or artist.lower() in cand1.lower():
            title = cand2
            artist = cand1
    else:
        # Check standard dashes e.g. 'Artist - Song Title' (standard YouTube video format)
        split_match = re.search(r"\s+[-–—|]\s+", title)
        if split_match:
            cand_artist = title[:split_match.start()].strip()
            cand_title = title[split_match.end():].strip()
            if not artist or artist.lower() in cand_artist.lower() or cand_artist.lower() in artist.lower():
                artist = cand_artist
                title = cand_title
            elif cand_title.lower() in artist.lower() or artist.lower() in cand_title.lower():
                artist = cand_title
                title = cand_artist

    # 6. Clean quotes around song titles e.g. Artist 'Song Name'
    quote_match = re.search(r'^(.*?)\s+["\x27“](.*?)["\x27”]$', title)
    if quote_match and not artist:
        artist = quote_match.group(1).strip()
        title = quote_match.group(2).strip()

    # 7. Normalize spaces
    title = re.sub(r"\s+", " ", title).strip()
    artist = re.sub(r"\s+", " ", artist).strip()

    return title, artist


def clean_title(title: str) -> str:
    """Removes leftover track suffixes for online lyric search."""
    if not title:
        return ""
    cleaned = re.sub(r"\(.*?(?:feat|remaster|version|edition|live|explicit|mono|stereo).*?\)", "", title, flags=re.IGNORECASE)
    cleaned = re.sub(r"\[.*?(?:feat|remaster|version|edition|live|explicit|mono|stereo).*?\]", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+-\s+(?:remaster|live|mono|stereo).*$", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned or title


def sanitize_filename(name: str) -> str:
    """Sanitizes artist/title for filesystem storage."""
    return re.sub(r'[\\/*?:"<>|]', "", name).strip()


def parse_lrc(lrc_text: str):
    """
    Parses an LRC string into a sorted list of (timestamp_seconds, text).
    Handles multiple timestamps per line and trims metadata tags.
    """
    entries = []
    for line in lrc_text.splitlines():
        line = line.strip()
        if not line:
            continue
        # Match one or more [mm:ss.xx] or [mm:ss]
        matches = list(re.finditer(r"\[(\d{1,2}):(\d{2}(?:\.\d+)?)\]", line))
        if not matches:
            continue
        text = line[matches[-1].end():].strip()
        for m in matches:
            try:
                minutes = int(m.group(1))
                seconds = float(m.group(2))
                t = minutes * 60.0 + seconds
                entries.append((t, text))
            except ValueError:
                continue
    entries.sort(key=lambda x: x[0])
    return entries


def find_local_lrc(artist: str, title: str, file_url: str = "") -> str:
    """Finds a matching local .lrc file if present."""
    # 1. Check beside file if it's a local audio file
    if file_url and file_url.startswith("file://"):
        local_audio_path = urllib.parse.unquote(file_url[7:])
        base_path, _ = os.path.splitext(local_audio_path)
        lrc_path = base_path + ".lrc"
        if os.path.isfile(lrc_path):
            try:
                with open(lrc_path, "r", encoding="utf-8", errors="replace") as f:
                    return f.read()
            except Exception:
                pass

    # 2. Check local directories
    safe_artist = sanitize_filename(artist)
    safe_title = sanitize_filename(title)
    candidate_names = [
        f"{safe_artist} - {safe_title}.lrc",
        f"{safe_title}.lrc",
        f"{safe_artist}/{safe_title}.lrc",
    ]

    for d in LOCAL_LYRIC_DIRS:
        for name in candidate_names:
            p = d / name
            if p.is_file():
                try:
                    with open(p, "r", encoding="utf-8", errors="replace") as f:
                        return f.read()
                except Exception:
                    pass

    return ""


def fetch_online_lrc(artist: str, title: str, album: str = "", duration: float = 0.0) -> str:
    """
    Fetches synced LRC from LRCLIB.net (free, fast, open-source synced lyrics API).
    Caches successful fetches locally.
    Supports both exact matching and search queries for YouTube Music & web browsers.
    """
    clean_t = clean_title(title)
    safe_artist = sanitize_filename(artist)
    safe_title = sanitize_filename(clean_t or title)
    cache_path = LYRIC_CACHE_DIR / f"{safe_artist} - {safe_title}.lrc"

    if cache_path.is_file():
        try:
            with open(cache_path, "r", encoding="utf-8", errors="replace") as f:
                return f.read()
        except Exception:
            pass

    headers = {"User-Agent": "LyricBar-Quickshell/1.0 (https://github.com/)"}

    # 1. Try exact get endpoint if artist is known
    if artist and clean_t:
        params = {
            "artist_name": artist,
            "track_name": clean_t,
        }
        if album:
            params["album_name"] = album
        if duration > 0:
            params["duration"] = int(duration)

        try:
            url = "https://lrclib.net/api/get?" + urllib.parse.urlencode(params)
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                synced = data.get("syncedLyrics")
                if synced:
                    with open(cache_path, "w", encoding="utf-8") as f:
                        f.write(synced)
                    return synced
        except Exception:
            pass

    # 2. Try search endpoint with queries (handles browser/YouTube tracks)
    search_queries = []
    if artist and clean_t:
        search_queries.append(f"{artist} {clean_t}".strip())
    if clean_t:
        search_queries.append(clean_t)

    for q in search_queries:
        try:
            url = "https://lrclib.net/api/search?" + urllib.parse.urlencode({"q": q})
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                results = json.loads(resp.read().decode("utf-8"))
                if isinstance(results, list) and len(results) > 0:
                    candidates = [item for item in results if item.get("syncedLyrics")]
                    if candidates:
                        best = None
                        # Prioritize match with similar duration
                        if duration > 0:
                            for c in candidates:
                                c_dur = float(c.get("duration", 0))
                                if abs(c_dur - duration) < 5.0:
                                    best = c
                                    break
                        if not best:
                            best = candidates[0]

                        synced = best.get("syncedLyrics")
                        if synced:
                            with open(cache_path, "w", encoding="utf-8") as f:
                                f.write(synced)
                            return synced
        except Exception:
            continue

    return ""


def score_player(service: str, props: dict) -> int:
    """
    Scores candidate MPRIS players to prioritize the most relevant media source.
    Prefers:
    1. 'Playing' status over 'Paused'
    2. Valid track titles and non-empty artist names
    3. High-fidelity browser integrations (e.g. Plasma Browser Integration) over raw browser binaries
    4. Dedicated media players (Spotify, Cider, Amberol, MPD, VLC)
    """
    if not props:
        return -1

    status = props.get("status", "")
    title = props.get("title", "").strip()
    artist = props.get("artist", "").strip()

    score = 0
    if status == "Playing":
        score += 1000
    elif status == "Paused":
        score += 400
    else:
        return -1

    # Heavy penalty if no identifiable track
    if not title:
        return score - 500

    # Rich metadata bonus
    if artist:
        score += 300
    else:
        score += 100

    if props.get("album"):
        score += 50
    if props.get("url"):
        score += 40
    if props.get("duration", 0) > 0:
        score += 30

    s_lower = service.lower()
    if "plasma-browser-integration" in s_lower:
        # Browser extension integration delivers high-fidelity DOM media metadata
        score += 200
    elif any(p in s_lower for p in ["spotify", "cider", "amberol", "mpd", "vlc", "rhythmbox", "audacious"]):
        score += 150
    elif any(b in s_lower for b in ["chromium", "chrome", "firefox", "brave", "zen"]):
        # Raw browser binary: give modest score if artist is present, otherwise discount
        if artist:
            score += 50
        else:
            score -= 100

    return score


class MprisPlayerDbus:
    """Connects to MPRIS via DBus session bus with full web browser & YouTube Music support."""
    def __init__(self):
        import dbus
        self.bus = dbus.SessionBus()

    def get_active_player(self, preferred_player=""):
        services = [s for s in self.bus.list_names() if s.startswith("org.mpris.MediaPlayer2.")]
        if not services:
            return None, None

        if preferred_player:
            for s in services:
                if preferred_player.lower() in s.lower():
                    props = self._get_player_props(s)
                    if props:
                        return s, props

        scored = []
        for s in services:
            if "playerctld" in s:
                continue
            props = self._get_player_props(s)
            if props:
                sc = score_player(s, props)
                if sc > 0:
                    scored.append((sc, s, props))

        if not scored:
            return None, None

        scored.sort(key=lambda x: x[0], reverse=True)
        best_sc, best_s, best_props = scored[0]
        return best_s, best_props

    def _get_player_props(self, service_name):
        import dbus
        try:
            obj = self.bus.get_object(service_name, "/org/mpris/MediaPlayer2")
            prop_iface = dbus.Interface(obj, "org.freedesktop.DBus.Properties")

            try:
                status = str(prop_iface.Get("org.mpris.MediaPlayer2.Player", "PlaybackStatus"))
            except Exception:
                status = "Stopped"

            try:
                meta = prop_iface.Get("org.mpris.MediaPlayer2.Player", "Metadata")
            except Exception:
                meta = {}

            # Safe position query (often 0 or raises in Chrome/Firefox)
            try:
                pos_us = int(prop_iface.Get("org.mpris.MediaPlayer2.Player", "Position"))
            except Exception:
                pos_us = 0

            raw_title = str(meta.get("xesam:title", ""))
            artists = meta.get("xesam:artist", [""])
            if isinstance(artists, (list, tuple, dbus.Array)):
                raw_artist = str(artists[0]) if len(artists) > 0 else ""
            else:
                raw_artist = str(artists) if artists else ""

            album = str(meta.get("xesam:album", ""))
            length_us = int(meta.get("mpris:length", 0))
            url = str(meta.get("xesam:url", ""))
            track_id = str(meta.get("mpris:trackid", ""))

            # Clean and normalize metadata (handles YouTube Music, YouTube, Chrome, Firefox)
            title, artist = clean_track_metadata(raw_title, raw_artist, album, url)

            player_name = str(service_name)
            if player_name.startswith("org.mpris.MediaPlayer2."):
                player_name = player_name[len("org.mpris.MediaPlayer2."):]

            return {
                "service": service_name,
                "player": player_name,
                "status": status,
                "title": title,
                "raw_title": raw_title,
                "artist": artist,
                "raw_artist": raw_artist,
                "album": album,
                "position": pos_us / 1_000_000.0,
                "duration": length_us / 1_000_000.0 if length_us else 0.0,
                "url": url,
                "track_id": track_id,
            }
        except Exception:
            return None


class MprisPlayerCtl:
    """Fallback connector using playerctl CLI."""
    def get_active_player(self, preferred_player=""):
        import subprocess
        cmd = ["playerctl"]
        if preferred_player:
            cmd.extend(["-p", preferred_player])
            cmd.extend([
                "metadata",
                "--format",
                "{{playerName}}|{{status}}|{{title}}|{{artist}}|{{album}}|{{position}}|{{mpris:length}}|{{mpris:trackid}}|{{xesam:url}}"
            ])
        else:
            cmd.extend([
                "-a",
                "metadata",
                "--format",
                "{{playerName}}|{{status}}|{{title}}|{{artist}}|{{album}}|{{position}}|{{mpris:length}}|{{mpris:trackid}}|{{xesam:url}}"
            ])
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, timeout=1.0).decode("utf-8").strip()
            if not out:
                return None, None

            scored = []
            for line in out.splitlines():
                line = line.strip()
                if not line:
                    continue
                parts = line.split("|")
                if len(parts) < 7:
                    continue
                player_name, status, raw_title, raw_artist, album, pos_str, length_str = parts[:7]
                track_id = parts[7] if len(parts) > 7 else ""
                url = parts[8] if len(parts) > 8 else ""

                try:
                    pos_val = float(pos_str) / 1_000_000.0 if pos_str else 0.0
                except ValueError:
                    pos_val = 0.0
                try:
                    len_val = float(length_str) / 1_000_000.0 if length_str else 0.0
                except ValueError:
                    len_val = 0.0

                clean_t, clean_a = clean_track_metadata(raw_title, raw_artist, album, url)

                props = {
                    "service": player_name,
                    "player": player_name,
                    "status": status,
                    "title": clean_t,
                    "raw_title": raw_title,
                    "artist": clean_a,
                    "raw_artist": raw_artist,
                    "album": album,
                    "position": pos_val,
                    "duration": len_val,
                    "url": url,
                    "track_id": track_id,
                }
                sc = score_player(player_name, props)
                if sc > 0:
                    scored.append((sc, player_name, props))

            if not scored:
                return None, None

            scored.sort(key=lambda x: x[0], reverse=True)
            best_sc, best_player, best_props = scored[0]
            return best_player, best_props
        except Exception:
            return None, None


def run_demo():
    """Simulates playback of a track with synced lyrics for testing transitions & auto-resize."""
    demo_track = {
        "artist": "Daft Punk",
        "title": "Get Lucky",
        "album": "Random Access Memories",
        "duration": 248.0,
    }
    demo_lyrics = [
        (0.0, "♪ Music Playing ♪"),
        (4.0, "Like the legend of the phoenix"),
        (8.5, "All ends with beginnings"),
        (13.0, "What keeps the planet spinning"),
        (17.5, "The force from the beginning"),
        (22.0, "We've come too far to give up who we are"),
        (27.0, "So let's raise the bar and our cups to the stars"),
        (32.0, "She's up all night 'til the sun"),
        (35.5, "I'm up all night to get some"),
        (39.0, "She's up all night for good fun"),
        (43.0, "I'm up all night to get lucky"),
        (47.0, "We're up all night to get lucky"),
        (51.0, "We're up all night to get lucky"),
        (55.0, "The present has no ribbon, your gift keeps on giving"),
        (60.0, "What is this I'm feeling?"),
        (64.0, "If you want to leave, I'm with it"),
    ]

    start_time = time.monotonic()
    last_idx = -1

    while True:
        elapsed = (time.monotonic() - start_time) % 68.0
        # Find current lyric line
        idx = 0
        for i, (ts, _) in enumerate(demo_lyrics):
            if elapsed >= ts:
                idx = i
            else:
                break

        if idx != last_idx:
            last_idx = idx
            text = demo_lyrics[idx][1]
            next_text = demo_lyrics[idx + 1][1] if idx + 1 < len(demo_lyrics) else ""
            data = {
                "text": text,
                "next": next_text,
                "artist": demo_track["artist"],
                "title": demo_track["title"],
                "album": demo_track["album"],
                "status": "Playing",
                "hasLyrics": True,
                "position": round(elapsed, 2),
                "duration": demo_track["duration"],
                "progress": round(elapsed / demo_track["duration"], 3),
            }
            print(json.dumps(data), flush=True)

        time.sleep(0.1)


def main():
    if "--demo" in sys.argv:
        run_demo()
        return

    plain_output = "--plain" in sys.argv
    preferred_player = ""
    for i, arg in enumerate(sys.argv):
        if arg == "--player" and i + 1 < len(sys.argv):
            preferred_player = sys.argv[i + 1]

    # Initialize connector
    connector = None
    try:
        import dbus
        connector = MprisPlayerDbus()
    except Exception:
        connector = MprisPlayerCtl()

    last_track_id = ""
    last_title = ""
    last_artist = ""
    lrc_entries = []
    lrc_timestamps = []
    has_synced_lyrics = False

    last_output_text = None
    last_output_status = None

    # Playback estimation variables
    last_pos = 0.0
    last_pos_time = time.monotonic()
    last_poll_time = 0.0

    while True:
        try:
            _, props = connector.get_active_player(preferred_player)

            # If DBus fails momentarily, try fallback
            if not props and isinstance(connector, MprisPlayerDbus):
                fallback = MprisPlayerCtl()
                _, props = fallback.get_active_player(preferred_player)

            if not props:
                # No player active
                if last_output_status != "Stopped":
                    data = {
                        "text": "",
                        "next": "",
                        "artist": "",
                        "title": "",
                        "album": "",
                        "status": "Stopped",
                        "hasLyrics": False,
                        "position": 0.0,
                        "duration": 0.0,
                        "progress": 0.0,
                    }
                    if plain_output:
                        print("", flush=True)
                    else:
                        print(json.dumps(data), flush=True)
                    last_output_text = ""
                    last_output_status = "Stopped"
                time.sleep(1.0)
                continue

            status = props.get("status", "Stopped")
            title = props.get("title", "")
            artist = props.get("artist", "")
            album = props.get("album", "")
            duration = props.get("duration", 0.0)
            track_id = props.get("track_id", "") or f"{artist}-{title}"
            reported_pos = props.get("position", 0.0)

            # Track changed
            if track_id != last_track_id or title != last_title or artist != last_artist:
                last_track_id = track_id
                last_title = title
                last_artist = artist
                last_pos = reported_pos
                last_pos_time = time.monotonic()

                # Fetch or load LRC
                raw_lrc = find_local_lrc(artist, title, props.get("url", ""))
                if not raw_lrc:
                    raw_lrc = fetch_online_lrc(artist, title, album, duration)

                if raw_lrc:
                    lrc_entries = parse_lrc(raw_lrc)
                    lrc_timestamps = [e[0] for e in lrc_entries]
                    has_synced_lyrics = len(lrc_entries) > 0
                else:
                    lrc_entries = []
                    lrc_timestamps = []
                    has_synced_lyrics = False

                last_output_text = None  # Force immediate update

            now = time.monotonic()

            # Resync position periodically (every 0.5s) to avoid drift
            if now - last_poll_time > 0.5:
                last_pos = reported_pos
                last_pos_time = now
                last_poll_time = now

            # Estimate current position
            if status == "Playing":
                est_pos = last_pos + (now - last_pos_time)
            else:
                est_pos = last_pos

            current_text = ""
            next_text = ""
            time_to_next = 0.25

            if has_synced_lyrics and lrc_timestamps:
                idx = bisect.bisect_right(lrc_timestamps, est_pos) - 1
                if idx >= 0:
                    current_text = lrc_entries[idx][1]
                    if idx + 1 < len(lrc_entries):
                        next_text = lrc_entries[idx + 1][1]
                        time_to_next = max(0.05, lrc_entries[idx + 1][0] - est_pos)
                else:
                    # Before first lyric
                    current_text = ""
                    if lrc_entries:
                        next_text = lrc_entries[0][1]
                        time_to_next = max(0.05, lrc_entries[0][0] - est_pos)
            else:
                current_text = ""
                next_text = ""
                time_to_next = 0.5

            progress = (est_pos / duration) if duration > 0 else 0.0

            # Emit output if lyric, status, or title changed
            if current_text != last_output_text or status != last_output_status:
                last_output_text = current_text
                last_output_status = status

                data = {
                    "text": current_text,
                    "next": next_text,
                    "artist": artist,
                    "title": title,
                    "album": album,
                    "player": props.get("player", ""),
                    "status": status,
                    "hasLyrics": has_synced_lyrics,
                    "position": round(est_pos, 2),
                    "duration": round(duration, 2),
                    "progress": round(progress, 3),
                }

                if plain_output:
                    print(current_text, flush=True)
                else:
                    print(json.dumps(data), flush=True)

            # Efficient sleep: calculate sleep interval until next lyric change
            sleep_time = min(0.35, max(0.05, time_to_next))
            time.sleep(sleep_time)

        except KeyboardInterrupt:
            break
        except Exception:
            time.sleep(1.0)


if __name__ == "__main__":
    main()
