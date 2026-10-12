#!/usr/bin/env bash
# SongRec turntable station installer for Raspberry Pi OS (64-bit preferred).
#
# Run from a normal login account:
#   chmod +x install-songrec-station.sh
#   ./install-songrec-station.sh "hw:1,0"
#
# Find the USB phono preamp's ALSA device with:
#   arecord -l
#
# The argument is optional; "default" is used when it is omitted.
set -Eeuo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this installer as the account that will own the station; it uses sudo when needed." >&2
  exit 1
fi

STATION_USER="${SUDO_USER:-$(id -un)}"
if [[ -z "${STATION_USER}" ]]; then
  echo "Cannot determine the user account that should own the station." >&2
  exit 1
fi

STATION_HOME="$(getent passwd "${STATION_USER}" | cut -d: -f6)"
if [[ -z "${STATION_HOME}" || ! -d "${STATION_HOME}" ]]; then
  echo "Cannot determine the home directory for ${STATION_USER}." >&2
  exit 1
fi

AUDIO_DEVICE="${1:-default}"
INSTALL_DIR="/opt/songrec-station"
DATA_DIR="/var/lib/songrec-station"
ENV_FILE="/etc/songrec-station.env"
SERVICE_FILE="/etc/systemd/system/songrec-station.service"

# Fail early if a required command is missing.
for cmd in sudo getent id awk cut; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Required command not found: ${cmd}" >&2
    exit 1
  fi
done

# Ask for sudo upfront so the rest of the script is not interrupted partway through.
if ! sudo -n true 2>/dev/null; then
  sudo true
fi

echo "Installing build and audio dependencies..."
sudo env DEBIAN_FRONTEND=noninteractive apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  alsa-utils build-essential ca-certificates curl git libasound2-dev \
  libssl-dev pkg-config python3

echo "Installing the current stable Rust toolchain for ${STATION_USER}..."
sudo -u "${STATION_USER}" -H bash -lc '
  export PATH="$HOME/.cargo/bin:$PATH"
  if ! command -v rustup >/dev/null 2>&1; then
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
  fi
  "$HOME/.cargo/bin/rustup" toolchain install stable --profile minimal
  "$HOME/.cargo/bin/rustup" default stable
'

echo "Compiling SongRec (this can take a while on a Pi 3+)..."
# No GUI, PipeWire, PulseAudio, MPRIS, or FFmpeg features are required: ALSA and WAV are enough.
sudo -u "${STATION_USER}" -H bash -lc '
  export PATH="$HOME/.cargo/bin:$PATH"
  cargo install --git https://github.com/marin-m/SongRec.git --locked \
    --no-default-features --force songrec
'

if [[ ! -x "${STATION_HOME}/.cargo/bin/songrec" ]]; then
  echo "SongRec binary was not installed under ${STATION_HOME}/.cargo/bin." >&2
  exit 1
fi

sudo install -d -o "${STATION_USER}" -g "${STATION_USER}" -m 0755 "${INSTALL_DIR}" "${DATA_DIR}"
sudo install -o "${STATION_USER}" -g "${STATION_USER}" -m 0755 \
  "${STATION_HOME}/.cargo/bin/songrec" "${INSTALL_DIR}/songrec"

echo "Installing the station worker..."
sudo tee "${INSTALL_DIR}/songrec_station.py" >/dev/null <<'PYTHON'
#!/usr/bin/env python3
"""Capture one fingerprint sample per vinyl track and publish web-friendly JSON."""
import json
import os
import shutil
import signal
import subprocess
import sys
import wave
from datetime import datetime, timezone
from pathlib import Path

ENV_PATH = "/etc/songrec-station.env"


def env_file(path):
    values = {}
    try:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
    except FileNotFoundError:
        pass
    return values


CONFIG = env_file(ENV_PATH)
DEVICE = CONFIG.get("AUDIO_DEVICE", "default")
RATE = int(CONFIG.get("SAMPLE_RATE", "44100"))
CHANNELS = int(CONFIG.get("CHANNELS", "1"))
SILENCE_RMS = int(CONFIG.get("SILENCE_RMS", "350"))
CHUNK_SECONDS = float(CONFIG.get("CHUNK_SECONDS", "0.25"))
START_AUDIO_SECONDS = float(CONFIG.get("START_AUDIO_SECONDS", "3"))
END_SILENCE_SECONDS = float(CONFIG.get("END_SILENCE_SECONDS", "4"))
CAPTURE_SECONDS = float(CONFIG.get("CAPTURE_SECONDS", "18"))
SONGREC_TIMEOUT_SECONDS = int(CONFIG.get("SONGREC_TIMEOUT_SECONDS", "90"))
DATA_DIR = Path(CONFIG.get("DATA_DIR", "/var/lib/songrec-station"))
SONGREC = CONFIG.get("SONGREC_BIN", "/opt/songrec-station/songrec")
FRAME_BYTES = max(2 * CHANNELS, int(RATE * CHUNK_SECONDS) * 2 * CHANNELS)


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def rms_s16le(data):
    """Return RMS for little-endian signed 16-bit PCM without extra packages."""
    samples = memoryview(data).cast("h")
    if not samples:
        return 0
    return int((sum(sample * sample for sample in samples) / len(samples)) ** 0.5)


def publish(payload):
    """Atomically replace the document polled by the web application."""
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    payload["updated_at"] = now()
    output = DATA_DIR / "current.json"
    temp = DATA_DIR / ".current.json.tmp"
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, output)


def append_history(payload):
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with (DATA_DIR / "history.ndjson").open("a", encoding="utf-8") as output:
        output.write(json.dumps(payload, ensure_ascii=False) + "\n")


def write_wav(raw, started_at):
    filename = "sample-" + started_at.replace(":", "-") + ".wav"
    path = DATA_DIR / filename
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(CHANNELS)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        wav.writeframes(raw)
    return path


def identify(raw, started_at):
    sample_path = write_wav(raw, started_at)
    publish({
        "state": "identifying",
        "sample_started_at": started_at,
        "sample_path": str(sample_path),
        "message": "Identifying this track...",
    })

    try:
        result = subprocess.run(
            [SONGREC, "recognize", "--json", str(sample_path)],
            capture_output=True,
            text=True,
            timeout=SONGREC_TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {
            "state": "not_found",
            "sample_started_at": started_at,
            "sample_path": str(sample_path),
            "error": "SongRec timed out.",
        }

    stdout = result.stdout.strip()
    if result.returncode != 0:
        return {
            "state": "not_found",
            "sample_started_at": started_at,
            "sample_path": str(sample_path),
            "error": result.stderr.strip() or "SongRec failed.",
        }

    try:
        songrec_response = json.loads(stdout)
    except json.JSONDecodeError:
        return {
            "state": "not_found",
            "sample_started_at": started_at,
            "sample_path": str(sample_path),
            "error": "No recognized song.",
            "songrec_stdout": stdout,
        }

    return {
        "state": "identified",
        "sample_started_at": started_at,
        "sample_path": str(sample_path),
        "songrec": songrec_response,
    }


def main():
    if shutil.which("arecord") is None:
        raise RuntimeError("arecord is not installed or not on PATH.")
    if not os.path.exists(SONGREC):
        raise RuntimeError(f"SongRec binary not found: {SONGREC}")

    publish({"state": "waiting_for_audio", "message": "Waiting for a record..."})

    command = [
        "arecord",
        "-q",
        "-D",
        DEVICE,
        "-f",
        "S16_LE",
        "-c",
        str(CHANNELS),
        "-r",
        str(RATE),
        "-t",
        "raw",
    ]
    recorder = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)

    def stop(*_):
        recorder.terminate()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    active_for = 0.0
    silent_for = 0.0
    capturing = False
    waiting_for_gap = False
    capture = bytearray()
    sample_started_at = None

    while True:
        data = recorder.stdout.read(FRAME_BYTES)
        if not data:
            stderr = recorder.stderr.read().decode(errors="replace")
            raise RuntimeError("arecord stopped: " + stderr)

        is_audio = rms_s16le(data) >= SILENCE_RMS
        duration = len(data) / (RATE * CHANNELS * 2)

        if waiting_for_gap:
            silent_for = silent_for + duration if not is_audio else 0.0
            if silent_for >= END_SILENCE_SECONDS:
                waiting_for_gap = False
                active_for = 0.0
                silent_for = 0.0
                publish({"state": "waiting_for_audio", "message": "Waiting for the next record..."})
            continue

        if not capturing:
            active_for = active_for + duration if is_audio else 0.0
            if active_for >= START_AUDIO_SECONDS:
                capturing = True
                capture = bytearray(data)
                sample_started_at = now()
                publish({
                    "state": "capturing",
                    "sample_started_at": sample_started_at,
                    "message": "Capturing one sample for identification...",
                })
            continue

        capture.extend(data)
        if len(capture) >= int(CAPTURE_SECONDS * RATE * CHANNELS * 2):
            outcome = identify(bytes(capture), sample_started_at)
            publish(outcome)
            append_history(outcome)
            capturing = False
            waiting_for_gap = True
            silent_for = 0.0


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as error:
        publish({"state": "error", "message": str(error)})
        raise
PYTHON
sudo chown "${STATION_USER}:${STATION_USER}" "${INSTALL_DIR}/songrec_station.py"
sudo chmod 0755 "${INSTALL_DIR}/songrec_station.py"

sudo tee "${ENV_FILE}" >/dev/null <<EOF
# Change AUDIO_DEVICE after running: arecord -l
AUDIO_DEVICE=${AUDIO_DEVICE}
# USB interfaces commonly support 44100 or 48000. Use the rate reported by arecord -D "${AUDIO_DEVICE}" --dump-hw-params /dev/zero.
SAMPLE_RATE=44100
CHANNELS=1
# RMS threshold (0-32767). Raise it if surface noise starts captures; lower it if music is missed.
SILENCE_RMS=350
START_AUDIO_SECONDS=3
END_SILENCE_SECONDS=4
CAPTURE_SECONDS=18
SONGREC_TIMEOUT_SECONDS=90
DATA_DIR=${DATA_DIR}
SONGREC_BIN=${INSTALL_DIR}/songrec
EOF
sudo chmod 0644 "${ENV_FILE}"

sudo tee "${SERVICE_FILE}" >/dev/null <<EOF
[Unit]
Description=SongRec turntable identification station
After=network-online.target sound.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${STATION_USER}
Group=${STATION_USER}
Environment=HOME=${STATION_HOME}
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${DATA_DIR}
ExecStart=${INSTALL_DIR}/songrec_station.py
Restart=on-failure
RestartSec=5
Nice=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=${DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now songrec-station.service

echo
echo "SongRec station is running. Check it with:"
echo "  sudo systemctl status songrec-station"
echo "  journalctl -u songrec-station -f"
echo "  cat ${DATA_DIR}/current.json"
echo
echo "Before building a web UI, confirm the correct capture device and tune SILENCE_RMS in ${ENV_FILE}."
