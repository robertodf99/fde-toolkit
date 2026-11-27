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
  "Screen Recording 2026-11-15 at 13.00.08.mov|154.310|3024x1964"
)

# Shots, in order. Consecutive shots with the same caption are one step (one number,
# one progress dot). Times are in the recording's own seconds (cut exactly, after
# decoding); speed 2 plays twice as fast, 0.75 holds a still screen longer. The crop
# is in recording pixels and is scaled to fit 1600 × 900. "gif" puts the shot in the
# README GIF too. Blur: rectangles x:y:w:h in recording pixels, separated by ";", each
# optionally "@from-to" (recording seconds) to blur only then.
#   recording | start | end | speed | crop w:h:x:y | gif | caption | blur
# Privacy: these ranges and crops were picked by looking at the recording's frames, and
# it holds the account name, home-folder paths, other sessions' tab titles and
# notifications, and the recording notes just outside them. After any change, extract
# frames of the rendered video and GIF at least every 0.5 s and look at every one, and
# look at EVERY frame of the first and last 0.5 s of each shot and of each crossfade:
# windows sliding between Spaces carry text past a fixed blur in a frame or two. Static
# blur rectangles only hold once the window is still (shot 10 starts at 122.0 s for
# that reason: the Space switch shows the desktop and Dock until ~121.8 s and the
# window slides in until ~121.9 s).
# The desktop shots share one crop: the top-right corner, where notifications appear.
SHOTS=(
  "13.00.08|21.6|23.6|1|1920:1080:0:880|no|Ask Claude Code something, then get on with your day|"
  "13.00.08|35.0|39.6|1|1152:720:1860:0|gif|Claude needs permission? Approve it from the notification|"
  "13.00.08|40.3|42.1|1|1152:720:1860:0|gif|Know the moment Claude finishes|"
  "13.00.08|52.6|57.0|1|1152:720:1860:0|gif|Or deny it, and Claude knows you said no|2370:368:630:60"
  "13.00.08|58.2|60.4|1|1152:720:1860:0|gif|Or deny it, and Claude knows you said no|"
  "13.00.08|106.4|113.6|1|1152:720:1860:0|gif|Claude asks? Pick an answer right from the notification|"
  "13.00.08|72.2|78.6|1|1152:720:1860:0|gif|Reply… shows every option plus a box for your own answer|"
  "13.00.08|95.6|98.9|0.75|1800:670:0:570|no|Every answer goes straight back to Claude Code|"
  "13.00.08|119.0|121.45|1|1152:720:1860:0|gif|Click a notification to jump to its session|"
  "13.00.08|122.0|125.0|1|2280:1600:20:290|gif|Click a notification to jump to its session|130:770:840:68"
  "13.00.08|147.6|151.5|1|1152:720:1860:0|no|Pause notifications from the Hook Me Up menu, and resume them|"
)
# A shot's recording is the RECORDINGS entry whose name contains its first field.

INTRO_SECONDS=3.5
OUTRO_SECONDS=4.5
FADE=0.4      # crossfade between shots, seconds
FPS=60
GIF_FPS=20
GIF_WIDTH=960
GIF_MAX_BYTES=5000000
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
rm -f "${OUT:?}"/shot-*.png "${OUT:?}"/gifshot-*.png "${OUT:?}"/clip-*.nut "${OUT:?}"/gifclip-*.nut \
  "${OUT:?}"/gif-*.png

# --- Shot list: steps and window sizes --------------------------------------------
# Steps are numbered twice: among all shots (the video) and among the "gif" shots (the
# GIF, which leaves some out and so has its own numbers and progress dots).
count=${#SHOTS[@]}
steps=0
gif_steps=0
previous=""
previous_gif=""
STEP=()
GIF_STEP=()
for shot in "${SHOTS[@]}"; do
  IFS='|' read -r _ _ _ _ _ gif caption _ <<<"$shot"
  [ "$caption" = "$previous" ] || steps=$((steps + 1))
  STEP+=("$steps")
  previous="$caption"
  if [ "$gif" = "gif" ]; then
    [ "$caption" = "$previous_gif" ] || gif_steps=$((gif_steps + 1))
    previous_gif="$caption"
  fi
  GIF_STEP+=("$gif_steps")
done
[ "$gif_steps" -gt 0 ] || fail "no shot is marked gif"

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
  [ "$gif" != "gif" ] || printf 'shot|%s|%s|%s|%s|%s|%s|%s|%s\n' "$OUT/gifshot-$i.png" "${GIF_STEP[$i]}" \
    "$gif_steps" "$x" "$y" "$w" "$h" "$caption" >>"$cards"
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
  graph="$graph,tpad=stop_mode=clone:stop_duration=1,trim=end_frame=${FRAMES[$i]}"
  # One clip per card: the video's, and the GIF's (its own step numbers) for "gif" shots.
  cards_in=(-loop 1 -framerate "$FPS" -i "$OUT/shot-$i.png")
  outputs=(-map "[o1]" -frames:v "${FRAMES[$i]}" "${LOSSLESS[@]}" "$OUT/clip-$i.nut")
  if [ "$gif" = "gif" ]; then
    cards_in+=(-loop 1 -framerate "$FPS" -i "$OUT/gifshot-$i.png")
    outputs+=(-map "[o2]" -frames:v "${FRAMES[$i]}" "${LOSSLESS[@]}" "$OUT/gifclip-$i.nut")
    graph="$graph,split[c1][c2];[c2][2:v]overlay=0:0:format=rgb:shortest=1,format=rgb24[o2];"
  else
    graph="$graph[c1];"
  fi
  graph="$graph[c1][1:v]overlay=0:0:format=rgb:shortest=1,format=rgb24[o1]"
  ffmpeg -v error -y -i "$file" "${cards_in[@]}" -filter_complex "$graph" "${outputs[@]}"
done

# --- Assembly: crossfades between consecutive clips ---------------------------------
# xfade_graph <clip>... prints a filter graph whose output is [out]; durations from frame counts.
xfade_graph() {
  local index=0 offset=0 label="0:v" clip frames duration
  for clip in "$@"; do
    frames="$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames \
      -of csv=p=0 "$clip")" || fail "ffprobe cannot count the frames of $clip"
    case "$frames" in
      '' | *[!0-9]*) fail "ffprobe gave \"$frames\" as the frame count of $clip" ;;
    esac
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
  [ "$gif" != "gif" ] || GIF_CLIPS+=("$OUT/gifclip-$i.nut")
done
VIDEO_CLIPS+=("$OUT/clip-outro.nut")

echo "Encoding $VIDEO"
args=()
while IFS= read -r -d '' arg; do args+=("$arg"); done < <(inputs "${VIDEO_CLIPS[@]}")
# Built first: a failure inside $(...) in ffmpeg's arguments would not stop the script.
video_graph="$(xfade_graph "${VIDEO_CLIPS[@]}")" || exit 1
ffmpeg -v error -y "${args[@]}" \
  -filter_complex "$video_graph;[out]scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv[v]" \
  -map "[v]" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -profile:v high -r "$FPS" \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -movflags +faststart -fflags +bitexact -map_metadata -1 -an "$VIDEO"

echo "Encoding $GIF"
args=()
while IFS= read -r -d '' arg; do args+=("$arg"); done < <(inputs "${GIF_CLIPS[@]}")
gif_graph="$(xfade_graph "${GIF_CLIPS[@]}")" || exit 1
ffmpeg -v error -y "${args[@]}" \
  -filter_complex "$gif_graph;[out]fps=$GIF_FPS,scale=$GIF_WIDTH:-2:flags=lanczos,format=rgb24[g]" \
  -map "[g]" -fflags +bitexact "$OUT/gif-%04d.png"
# Full motion quality: lower values leave ghosts of earlier frames on the flat backgrounds.
gifski --quiet --fps "$GIF_FPS" --width "$GIF_WIDTH" --quality 85 --motion-quality 100 -o "$OUT/demo.gif" "$OUT"/gif-*.png
bytes="$(wc -c <"$OUT/demo.gif" | tr -d ' ')"
[ "$bytes" -lt "$GIF_MAX_BYTES" ] || fail "the GIF is $bytes bytes (limit $GIF_MAX_BYTES): lower GIF_WIDTH or the quality"
cp "$OUT/demo.gif" "$GIF"

echo "Demo: $VIDEO"
echo "GIF:  $GIF ($bytes bytes)"
