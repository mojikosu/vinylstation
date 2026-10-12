# SongRec turntable station

`install-songrec-station.sh` provisions a Raspberry Pi 3+ running Raspberry Pi OS and creates a `systemd` service that identifies vinyl tracks from a USB phono preamp.

Install from the account that will run the station:

```bash
arecord -l
./install-songrec-station.sh "hw:1,0"
```

Use the exact device string reported for the USB capture device. If it is unknown, omit the argument to try ALSA's `default` device.

The service writes a stable, web-friendly JSON document to `/var/lib/songrec-station/current.json` and an append-only recognition log to `/var/lib/songrec-station/history.ndjson`. A web server should serve or read `current.json`; its `songrec` field intentionally preserves the complete SongRec/Shazam response, so the UI can use artwork, artist, album, genres, links, and other details that upstream returns.

## Why no Liquidsoap

Liquidsoap is not needed for the first version. The service reads the ALSA stream directly, measures RMS volume every quarter-second, and follows this state machine:

```text
silent → 3 s of audio → capture one 18 s WAV → SongRec once → wait for 4 s silence → silent
```

That gate is the important part: an identified track cannot generate repeated requests or competing identifications until the needle reaches a genuinely quiet inter-track gap. It produces exactly one recognition attempt per audible segment, including one `not_found` event when SongRec cannot match it.

Liquidsoap would be justified later only if you also need network audio routing, recording/transcoding, or advanced broadcast-style segmentation. It does not make the recognition decision itself more reliable, and it adds significant complexity and memory pressure to a Pi 3+.

## Calibration

With a record stopped, then playing, view the input level in another terminal:

```bash
arecord -D "hw:1,0" -f S16_LE -c 1 -r 44100 -t raw | \
  python3 -c 'import sys; import math; [print(int(math.sqrt(sum(x*x for x in memoryview(sys.stdin.buffer.read(22050)).cast("h"))/11025))) for _ in iter(int, 1)]'
```

Choose `SILENCE_RMS` in `/etc/songrec-station.env` above the turntable's surface/noise-floor reading but comfortably below quiet music. Then restart:

```bash
sudo systemctl restart songrec-station
journalctl -u songrec-station -f
```

If `44100` is unsupported by the USB device, change `SAMPLE_RATE` to `48000`; verify the hardware capabilities with:

```bash
arecord -D "hw:1,0" --dump-hw-params -f S16_LE -c 1 -r 44100 -t raw /dev/zero
```

Gapless records are the one intentional limitation: a silence-gated system treats a continuous side as one segment. For gapless albums, add a manual “identify now” button to the eventual web UI or move to a more sophisticated novelty/track-change detector; do not switch to unrestricted continuous SongRec polling.

SongRec’s documented CLI offers one-shot `recognize`, continuous `listen`, and JSON/CSV output. This station deliberately uses the one-shot JSON mode on a WAV sample, because JSON keeps nested metadata intact for a richer web page. [SongRec README](https://github.com/marin-m/SongRec#sample-usage) · [current command options](https://man.archlinux.org/man/songrec-recognize.1.en)
