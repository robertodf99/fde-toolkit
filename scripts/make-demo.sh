#!/bin/bash
# Builds the demo video and the README's GIF from macOS screen recordings:
#   .build/demo/hook-me-up-demo.mp4   1920 × 1080, 60 fps, H.264 High, no audio
#   docs/images/demo.gif              the core flow only (shots marked "gif")
# Each shot is a cropped piece of a recording shown as a rounded window over the brand
# background, under a numbered caption, between an intro and an outro card. The stills
# come from scripts/make-demo-cards.swift and scripts/make-logo.swift (this ffmpeg has
# no text rendering); intermediates go to .build/demo/. Recordings are never committed.
#
# Usage: scripts/make-demo.sh [recordings-folder]   (default: ~/Desktop)
# Needs ffmpeg, ffprobe and gifski (Homebrew) and Swift (Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

RECORDINGS_DIR="${1:-$HOME/Desktop}"

# ---------------------------------------------------------------------------------
# Recordings: the files the shots cut from, with the duration (seconds) and size each
# must have, so a re-recorded or renamed file is caught before anything is rendered.
#   name | duration | width x height
RECORDINGS=(
  "Screen Recording 2026-11-14 at 22.32.08.mov|40.567|3024x1964"
  "Screen Recording 2026-11-14 at 22.05.01.mov|32.493|3024x1964"
  "Screen Recording 2026-11-14 at 22.44.21.mov|33.995|3024x1964"
  "Screen Recording 2026-11-14 at 22.20.23.mov|99.073|3024x1964"
)

# Shots, in order. Consecutive shots with the same caption are one step (one number,
# one progress dot). Times are in the recording's own seconds (cut exactly, after
# decoding); speed 2 plays twice as fast. The crop is in recording pixels and is scaled
# to fit 1600 × 900. "gif" puts the shot in the README GIF too. Blur: rectangles
# x:y:w:h in recording pixels, separated by ";", each optionally "@from-to" (recording
# seconds) to blur only then.
#   recording | start | end | speed | crop w:h:x:y | gif | caption | blur
# Privacy: these ranges and crops were picked by looking at the recordings' frames, and
# the recordings hold e-mail addresses, browser history, other sites, other projects
# and home-folder paths just outside them. After any change, extract frames of the
# rendered video at least every 0.5 s and look at every one before publishing it.
SHOTS=(
  "22.32.08|2.0|12.2|2|1920:1080:700:880|gif|Ask Claude Code something, then get on with your day|"
  "22.05.01|12.0|21.8|1.25|1104:620:1920:0|gif|Claude asks: pick an answer right from the notification|"
  "22.05.01|23.8|27.9|1.5|2200:1000:690:400|gif|Your answer goes straight back to Claude Code|"
  # "<permission recording>|...|...|1|...|gif|Approve or deny a tool without leaving what you're doing|"
  # "<plan recording>|...|...|1|...|gif|Approve Claude's plan, or ask for changes|"
  "22.44.21|14.3|21.0|1|964:620:2060:0|gif|Reply… shows every option plus a box for your own answer|"
  # "<free-text recording>|...|...|1|...|gif|Type your own answer and send it from the notification|"
  "22.44.21|24.3|26.7|1|944:531:2080:0|gif|Know the moment Claude finishes|"
  "22.20.23|28.2|30.44|1|1104:620:1920:0|gif|Click any notification to jump back to the session|"
  "22.20.23|30.44|34.6|1|3024:1964:0:0|gif|Click any notification to jump back to the session|0:960:3024:400@30-31.8"
  # "<menu-bar recording>|...|...|1|...|no|Pause notifications from the ✻ menu, and resume them|"
  # "<install recording>|...|...|2|...|no|Install with one command|"
)
# A shot's recording is the RECORDINGS entry whose name contains its first field.

INTRO_SECONDS=3
OUTRO_SECONDS=4
FADE=0.4      # crossfade between shots, seconds
FPS=60
GIF_FPS=20
GIF_WIDTH=960
GIF_MAX_BYTES=$((5 * 1024 * 1024))
# The window area: shots are scaled to fit this box, centred under the caption bar.
BOX_W=1600
BOX_H=900
BOX_TOP=120
# ---------------------------------------------------------------------------------

OUT=.build/demo
VIDEO="$OUT/hook-me-up-demo.mp4"
GIF=docs/images/demo.gif

fail() {
  echo "make-demo: $*" >&2
  exit 1
}

for tool in ffmpeg ffprobe gifski; do
  command -v "$tool" >/dev/null || fail "$tool not found (brew install $tool)"
done
# The xcode-select toolchain as is; Xcode's only when the Command Line Tools are selected,
# DEVELOPER_DIR is unset and Xcode is in /Applications (same rule as the Makefile).
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ] \
  && xcode-select -p 2>/dev/null | grep -q CommandLineTools; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# --- Inputs -----------------------------------------------------------------------
[ -d "$RECORDINGS_DIR" ] || fail "no folder $RECORDINGS_DIR"
for entry in "${RECORDINGS[@]}"; do
  IFS='|' read -r name duration size <<<"$entry"
  file="$RECORDINGS_DIR/$name"
  [ -f "$file" ] || fail "missing recording: $file"
  probe="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height:format=duration \
    -of default=noprint_wrappers=1 "$file")" || fail "ffprobe cannot read $file"
  actual_size="$(awk -F= '$1=="width"{w=$2} $1=="height"{h=$2} END{print w "x" h}' <<<"$probe")"
  actual_duration="$(awk -F= '$1=="duration"{print $2}' <<<"$probe")"
  [ "$actual_size" = "$size" ] || fail "$name is $actual_size, expected $size"
  awk -v a="$actual_duration" -v e="$duration" 'BEGIN{d=a-e; exit !(d<0.05 && d>-0.05)}' \
    || fail "$name lasts ${actual_duration}s, expected ${duration}s (a different recording?)"
done

recording_for() {
  local entry name
  for entry in "${RECORDINGS[@]}"; do
    name="${entry%%|*}"
    case "$name" in *"$1"*)
      echo "$name"
      return 0
      ;;
    esac
  done
  return 1
}

mkdir -p "$OUT"
rm -f "${OUT:?}"/shot-*.png "${OUT:?}"/clip-*.nut "${OUT:?}"/gif-*.png

# --- Shot list: steps and window sizes --------------------------------------------
count=${#SHOTS[@]}
steps=0
previous=""
STEP=()
for shot in "${SHOTS[@]}"; do
  IFS='|' read -r _ _ _ _ _ _ caption _ <<<"$shot"
  [ "$caption" = "$previous" ] || steps=$((steps + 1))
  STEP+=("$steps")
  previous="$caption"
done

cards="$OUT/cards.txt"
logo="$OUT/logo.png"
{
  echo "intro|$OUT/intro.png|$logo"
  echo "outro|$OUT/outro.png|$logo"
} >"$cards"
GEOMETRY=()
FRAMES=()
for i in $(seq 0 $((count - 1))); do
  IFS='|' read -r key start end speed crop gif caption blur <<<"${SHOTS[$i]}"
  recording_for "$key" >/dev/null || fail "shot $((i + 1)): no recording matches \"$key\""
  IFS=':' read -r cw ch cx cy <<<"$crop"
  # Fit the crop into the box, even sizes, centred.
  read -r w h x y < <(awk -v cw="$cw" -v ch="$ch" -v bw="$BOX_W" -v bh="$BOX_H" -v top="$BOX_TOP" 'BEGIN{
    if (cw * bh >= ch * bw) { w = bw; h = 2 * int(bw * ch / cw / 2 + 0.5) }
    else { h = bh; w = 2 * int(bh * cw / ch / 2 + 0.5) }
    printf "%d %d %d %d\n", w, h, (1920 - w) / 2, top + (bh - h) / 2 }')
  GEOMETRY+=("$w $h $x $y")
  frames="$(awk -v s="$start" -v e="$end" -v v="$speed" -v f="$FPS" 'BEGIN{printf "%d", (e - s) / v * f + 0.5}')"
  [ "$frames" -gt 0 ] || fail "shot $((i + 1)): end must come after start"
  FRAMES+=("$frames")
  printf 'shot|%s|%s|%s|%s|%s|%s|%s|%s\n' "$OUT/shot-$i.png" "${STEP[$i]}" "$steps" "$x" "$y" "$w" "$h" \
    "$caption" >>"$cards"
done

echo "Drawing the logo and cards"
xcrun swift scripts/make-logo.swift --logo 640 "$logo" >/dev/null
xcrun swift scripts/make-demo-cards.swift <"$cards"

# --- Clips: every shot and card as lossless RGB, exactly its number of frames -------
LOSSLESS=(-c:v libx264rgb -qp 0 -preset ultrafast -pix_fmt rgb24 -an)

render_card() { # <png> <seconds> <clip>
  ffmpeg -v error -y -loop 1 -framerate "$FPS" -i "$1" -vf "format=rgb24" \
    -frames:v "$(awk -v s="$2" -v f="$FPS" 'BEGIN{printf "%d", s * f}')" "${LOSSLESS[@]}" "$3"
}

echo "Rendering the intro and outro"
render_card "$OUT/intro.png" "$INTRO_SECONDS" "$OUT/clip-intro.nut"
render_card "$OUT/outro.png" "$OUTRO_SECONDS" "$OUT/clip-outro.nut"

for i in $(seq 0 $((count - 1))); do
  IFS='|' read -r key start end speed crop gif caption blur <<<"${SHOTS[$i]}"
  read -r w h x y <<<"${GEOMETRY[$i]}"
  file="$RECORDINGS_DIR/$(recording_for "$key")"
  echo "Rendering shot $((i + 1))/$count: $key $start-${end}s"
  # trim keeps the recording's timestamps, so blur windows are in recording seconds.
  graph="[0:v]trim=start=$start:end=$end"
  n=0
  if [ -n "$blur" ]; then
    IFS=';' read -r -a rects <<<"$blur"
    for rect in "${rects[@]}"; do
      area="${rect%%@*}"
      IFS=':' read -r bx by bw bh <<<"$area"
      enable=""
      if [ "$area" != "$rect" ]; then
        when="${rect#*@}"
        enable=":enable='between(t,${when%-*},${when#*-})'"
      fi
      graph="$graph[b$n];[b$n]split[m$n][p$n];[p$n]crop=$bw:$bh:$bx:$by,gblur=sigma=40:steps=3[q$n];"
      graph="$graph[m$n][q$n]overlay=$bx:$by$enable"
      n=$((n + 1))
    done
  fi
  graph="$graph,setpts=(PTS-STARTPTS)/$speed,fps=$FPS,crop=$crop"
  graph="$graph,scale=$w:$h:flags=lanczos+accurate_rnd+full_chroma_int:in_color_matrix=bt709:in_range=tv"
  graph="$graph,format=rgb24,pad=1920:1080:$x:$y:color=black"
  graph="$graph,tpad=stop_mode=clone:stop_duration=1,trim=end_frame=${FRAMES[$i]}[clip];"
  graph="$graph[1:v]format=rgba[card];[clip][card]overlay=0:0:format=rgb:shortest=1,format=rgb24"
  ffmpeg -v error -y -i "$file" -loop 1 -framerate "$FPS" -i "$OUT/shot-$i.png" -filter_complex "$graph" \
    -frames:v "${FRAMES[$i]}" "${LOSSLESS[@]}" "$OUT/clip-$i.nut"
done

# --- Assembly: crossfades between consecutive clips ---------------------------------
# xfade_graph <clip>... prints a filter graph whose output is [out]; durations from frame counts.
xfade_graph() {
  local index=0 offset=0 label="0:v" clip frames duration
  for clip in "$@"; do
    frames="$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames \
      -of csv=p=0 "$clip")"
    duration="$(awk -v n="$frames" -v f="$FPS" 'BEGIN{printf "%.6f", n / f}')"
    if [ "$index" -gt 0 ]; then
      printf '[%s][%d:v]xfade=transition=fade:duration=%s:offset=%s[x%d];' \
        "$label" "$index" "$FADE" "$offset" "$index"
      label="x$index"
    fi
    offset="$(awk -v o="$offset" -v d="$duration" -v fd="$FADE" -v i="$index" \
      'BEGIN{printf "%.6f", (i == 0 ? d : o + d) - fd}')"
    index=$((index + 1))
  done
  printf '[%s]null[out]' "$label"
}

inputs() { # <clip>... → -i <clip> ...
  local clip
  for clip in "$@"; do printf '%s\0%s\0' -i "$clip"; done
}

VIDEO_CLIPS=("$OUT/clip-intro.nut")
GIF_CLIPS=()
for i in $(seq 0 $((count - 1))); do
  VIDEO_CLIPS+=("$OUT/clip-$i.nut")
  IFS='|' read -r _ _ _ _ _ gif _ _ <<<"${SHOTS[$i]}"
  [ "$gif" != "gif" ] || GIF_CLIPS+=("$OUT/clip-$i.nut")
done
VIDEO_CLIPS+=("$OUT/clip-outro.nut")

echo "Encoding $VIDEO"
args=()
while IFS= read -r -d '' arg; do args+=("$arg"); done < <(inputs "${VIDEO_CLIPS[@]}")
ffmpeg -v error -y "${args[@]}" \
  -filter_complex "$(xfade_graph "${VIDEO_CLIPS[@]}");[out]scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv[v]" \
  -map "[v]" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high -r "$FPS" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -movflags +faststart -fflags +bitexact -map_metadata -1 -an "$VIDEO"

echo "Encoding $GIF"
[ "${#GIF_CLIPS[@]}" -gt 0 ] || fail "no shot is marked gif"
args=()
while IFS= read -r -d '' arg; do args+=("$arg"); done < <(inputs "${GIF_CLIPS[@]}")
ffmpeg -v error -y "${args[@]}" \
  -filter_complex "$(xfade_graph "${GIF_CLIPS[@]}");[out]fps=$GIF_FPS,scale=$GIF_WIDTH:-2:flags=lanczos,format=rgb24[g]" \
  -map "[g]" -fflags +bitexact "$OUT/gif-%04d.png"
gifski --quiet --fps "$GIF_FPS" --width "$GIF_WIDTH" --quality 80 -o "$OUT/demo.gif" "$OUT"/gif-*.png
bytes="$(wc -c <"$OUT/demo.gif" | tr -d ' ')"
[ "$bytes" -lt "$GIF_MAX_BYTES" ] || fail "the GIF is $bytes bytes (limit $GIF_MAX_BYTES): lower GIF_WIDTH or the quality"
cp "$OUT/demo.gif" "$GIF"

echo "Demo: $VIDEO"
echo "GIF:  $GIF ($bytes bytes)"
