#!/usr/bin/env python3
"""Génère le master.m3u8 et les playlists média de l'échelle HLS de test Yélé.

Usage : build_master_playlist.py <dossier_sortie>

Le dossier doit contenir, pour chaque variante, les fichiers fMP4 téléchargés
par fetch_akamai_clip.sh (init *_0.m4v/.m4a + segments numérotés).
Les codecs/bande passantes sont ceux du manifeste DASH Akamai BBB 30fps.
"""
import os
import sys

# Débits annoncés : valeurs par défaut = échelle Akamai d'origine. Surchargeables
# par variables d'environnement BANDWIDTH_720/1080/2160 quand les variantes ont
# été ré-encodées à d'autres débits (scripts/rebuild_ladder_mobile_bitrates.sh :
# débits calés sur ce que YouTube sert sur mobile — 720p ~2,5 Mb/s,
# 1080p ~4 Mb/s — au lieu des 4,95/9,91 Mb/s Akamai).
VARIANTS = [
    # (répertoire, playlist média, résolution, débit, codecs vidéo, fps)
    ("bbb_30fps_1280x720_4000k", "720p.m3u8", "1280x720",
     int(os.environ.get("BANDWIDTH_720", "4952892")), "avc1.64001f", 30.0),
    ("bbb_30fps_1920x1080_8000k", "1080p.m3u8", "1920x1080",
     int(os.environ.get("BANDWIDTH_1080", "9914554")), "avc1.640028", 30.0),
    ("bbb_30fps_3840x2160_12000k", "2160p.m3u8", "3840x2160",
     int(os.environ.get("BANDWIDTH_2160", "14931538")), "avc1.640033", 30.0),
]
AUDIO_DIR = "bbb_a64k"
AUDIO_PLAYLIST = "audio.m3u8"
AUDIO_BANDWIDTH = 67071
AUDIO_CODEC = "mp4a.40.5"

# Durée nominale d'un segment (4,0 s vidéo / 4,0107 s audio → TARGETDURATION 5).
VIDEO_SEG_DURATION = 4.0
AUDIO_SEG_DURATION = 4.0107


def media_playlist(path: str, uris: list[str], init: str,
                   seg_duration: float) -> None:
    target = int(seg_duration) + 1 if seg_duration % 1 else int(seg_duration)
    lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:7",
        f"#EXT-X-TARGETDURATION:{target}",
        "#EXT-X-PLAYLIST-TYPE:VOD",
        f'#EXT-X-MAP:URI="{init}"',
    ]
    for u in uris:
        lines += [f"#EXTINF:{seg_duration:.4f},", u]
    lines.append("#EXT-X-ENDLIST")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main(out_dir: str) -> None:
    master = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-INDEPENDENT-SEGMENTS", ""]

    # Piste audio seule.
    audio_files = sorted(
        f for f in os.listdir(os.path.join(out_dir, AUDIO_DIR))
        if f.endswith(".m4a") and not f.endswith("_0.m4a")
    )
    media_playlist(
        os.path.join(out_dir, AUDIO_PLAYLIST),
        [f"{AUDIO_DIR}/{f}" for f in audio_files],
        f"{AUDIO_DIR}/{AUDIO_DIR}_0.m4a",
        AUDIO_SEG_DURATION,
    )
    master.append(
        f'#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="Audio",'
        f"DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"und\","
        f'URI="{AUDIO_PLAYLIST}"'
    )

    for rep, playlist, res, bandwidth, codec, fps in VARIANTS:
        files = sorted(
            f for f in os.listdir(os.path.join(out_dir, rep))
            if f.endswith(".m4v") and not f.endswith("_0.m4v")
        )
        media_playlist(
            os.path.join(out_dir, playlist),
            [f"{rep}/{f}" for f in files],
            f"{rep}/{rep}_0.m4v",
            VIDEO_SEG_DURATION,
        )
        codecs = f'"{codec},{AUDIO_CODEC}"'
        master.append(
            f"#EXT-X-STREAM-INF:BANDWIDTH={bandwidth},"
            f"AVERAGE-BANDWIDTH={bandwidth},RESOLUTION={res},"
            f"FRAME-RATE={fps:.3f},CODECS={codecs},AUDIO=\"aud\""
        )
        master.append(playlist)

    # Variante audio seule (utile pour un contrôle hors vidéo).
    master.append(f"#EXT-X-STREAM-INF:BANDWIDTH={AUDIO_BANDWIDTH},"
                  f'CODECS="{AUDIO_CODEC}",AUDIO="aud"')
    master.append(AUDIO_PLAYLIST)

    with open(os.path.join(out_dir, "master.m3u8"), "w") as f:
        f.write("\n".join(master) + "\n")
    print(f"master.m3u8 écrit : {len(VARIANTS)} variantes vidéo + audio, "
          f"{len(audio_files)} segments audio")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: build_master_playlist.py <dossier_sortie>")
    main(sys.argv[1])
