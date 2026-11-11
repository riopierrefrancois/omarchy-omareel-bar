#!/usr/bin/env bash
# Helper for the Omareel bar widget. Reads and writes Omareel's own recording
# settings (~/.config/omareel/settings.json), the file its launcher uses, so the
# bar and the launcher always agree.
#
#   tools.sh state                 JSON: current choices plus the cameras and microphones found
#   tools.sh set <key> <value>     key: systemAudio | microphone | microphoneDevice | webcam | webcamDevice
set -euo pipefail

settings="${XDG_CONFIG_HOME:-$HOME/.config}/omareel/settings.json"

current() {
  if [[ -s $settings ]] && jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
    cat "$settings"
  else
    echo '{}'
  fi
}

cameras() {
  # Each camera's first node, by its stable /dev/v4l/by-id path (the path Omareel saves).
  local link node name
  for link in /dev/v4l/by-id/*-video-index0; do
    [[ -e $link ]] || continue
    node=$(basename "$(readlink -f "$link")")
    name=$(cat "/sys/class/video4linux/$node/name" 2>/dev/null || echo "$node")
    jq -cn --arg value "$link" --arg text "$name" '{value: $value, text: $text}'
  done | jq -cs '.'
}

microphones() {
  # The same list Omareel's launcher shows: the default input plus ALSA inputs.
  { timeout 5 gpu-screen-recorder --list-audio-devices 2>/dev/null || true; } |
    awk -F'|' '$1 == "default_input" || $1 ~ /^alsa_input\./ { print }' |
    while IFS='|' read -r value text; do
      jq -cn --arg value "$value" --arg text "$text" '{value: $value, text: $text}'
    done | jq -cs 'if length == 0 then [{value: "default_input", text: "Default input"}] else . end'
}

case "${1:-}" in
  state)
    # Like `omareel record`: the chosen camera while it is plugged in, else the one in use.
    cams=$(cameras)
    current | jq -c --argjson cameras "$cams" --argjson present "$(jq -c '[.[].value]' <<<"$cams")" --argjson mics "$(microphones)" '{
      systemAudio: (.systemAudio // true),
      microphone: (.microphone // true),
      microphoneDevice: (.microphoneDevice // "default_input"),
      webcam: (.webcam.enabled // false),
      webcamDevice: (if ((.webcam.chosenDevice // "") as $c | $present | index($c)) then .webcam.chosenDevice else (.webcam.device // "") end),
      cameras: $cameras,
      microphones: $mics
    }'
    ;;
  set)
    key=${2:?key}; value=${3:?value}
    case $key in
      systemAudio|microphone) filter='.[$key] = ($value == "true")' ;;
      microphoneDevice) filter='.microphoneDevice = $value' ;;
      webcam) filter='.webcam = ((.webcam // {}) | .enabled = ($value == "true"))' ;;
      webcamDevice) filter='.webcam = ((.webcam // {}) | .device = $value | .chosenDevice = $value)' ;;
      *) echo "unknown key: $key" >&2; exit 2 ;;
    esac
    mkdir -p "$(dirname "$settings")"
    tmp=$(mktemp "$settings.XXXXXX")
    current | jq --indent 4 --arg key "$key" --arg value "$value" "$filter" > "$tmp"
    mv "$tmp" "$settings"
    ;;
  *)
    echo "usage: tools.sh state | set <key> <value>" >&2
    exit 2
    ;;
esac
