#!/bin/bash
# One-Click Build Demo Video Generator
# Generates title cards, music, and assembles the final 1-minute demo video.
# Requires: magick (ImageMagick 7), ffmpeg
# Usage: ./scripts/generate-video.sh [screen-recording.mov]

set -e
cd "$(dirname "$0")/.."

OUT="$HOME/Desktop/build-video"
mkdir -p "$OUT"

FONT_BOLD="/System/Library/Fonts/Helvetica.ttc"
FONT="/System/Library/Fonts/Helvetica.ttc"
RECORDING="${1:-$OUT/build_raw.mov}"

echo "=== Generating title cards ==="

# Card 1: The problem (4 seconds)
magick -size 1920x1080 xc:black \
  -gravity center \
  -font "$FONT_BOLD" -pointsize 64 -fill white -annotate +0-40 "Real projects are messy." \
  -font "$FONT" -pointsize 28 -fill '#888888' -annotate +0+30 "Partial files. No production gerbers. No BOM." \
  "$OUT/card1.png"

# Card 2: The solution (4 seconds)
magick -size 1920x1080 xc:black \
  -gravity center \
  -font "$FONT_BOLD" -pointsize 80 -fill white -annotate +0-50 "Parts Build" \
  -font "$FONT" -pointsize 32 -fill '#3399FF' -annotate +0+20 "From repo to order. One click." \
  -font "$FONT" -pointsize 22 -fill '#666666' -annotate +0+70 "source.parts" \
  "$OUT/card2.png"

# Card 3: CTA (4 seconds)
magick -size 1920x1080 xc:black \
  -gravity center \
  -font "$FONT_BOLD" -pointsize 60 -fill white -annotate +0-30 "source.parts/build" \
  -font "$FONT" -pointsize 28 -fill '#3399FF' -annotate +0+30 "From GitHub to factory. Instantly." \
  "$OUT/card3.png"

# Card 4: Closing (3 seconds)
magick -size 1920x1080 xc:black \
  -gravity center \
  -font "$FONT" -pointsize 36 -fill '#3399FF' -annotate +0-15 "F.inc Hack Night 2026" \
  -font "$FONT" -pointsize 20 -fill '#555555' -annotate +0+30 "Built with Source Parts API" \
  "$OUT/card4.png"

echo "=== Converting cards to video ==="

for i in 1 2; do
  ffmpeg -y -loop 1 -i "$OUT/card${i}.png" -c:v libx264 -t 4 -pix_fmt yuv420p -r 30 "$OUT/card${i}.mov" 2>/dev/null
done
for i in 3 4; do
  DUR=$( [ "$i" = "4" ] && echo 3 || echo 4 )
  ffmpeg -y -loop 1 -i "$OUT/card${i}.png" -c:v libx264 -t "$DUR" -pix_fmt yuv420p -r 30 "$OUT/card${i}.mov" 2>/dev/null
done

echo "=== Generating ambient music ==="

ffmpeg -y \
  -f lavfi -i "sine=frequency=110:duration=65" \
  -f lavfi -i "sine=frequency=165:duration=65" \
  -f lavfi -i "sine=frequency=220:duration=65" \
  -filter_complex "[0:a][1:a][2:a]amix=inputs=3:duration=longest,volume=0.08,aecho=0.8:0.88:60:0.4,lowpass=f=800[a]" \
  -map "[a]" -c:a aac -b:a 128k "$OUT/music.m4a" 2>/dev/null

echo "=== Checking screen recording ==="

if [ ! -f "$RECORDING" ]; then
  echo ""
  echo "ERROR: No screen recording found at $RECORDING"
  echo ""
  echo "To record, run:"
  echo "  ffmpeg -f avfoundation -framerate 30 -i \"1:none\" -t 70 -c:v libx264 -pix_fmt yuv420p $OUT/build_raw.mov"
  echo ""
  echo "Or provide path: ./scripts/generate-video.sh /path/to/recording.mov"
  exit 1
fi

echo "=== Processing screen recording ==="

# Get recording dimensions and scale to 1920x1080
ffmpeg -y -i "$RECORDING" \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,setpts=0.8*PTS" \
  -c:v libx264 -preset fast -pix_fmt yuv420p -r 30 -an \
  "$OUT/recording_scaled.mov" 2>/dev/null

echo "=== Assembling final video ==="

# Create concat file
cat > "$OUT/filelist.txt" <<CONCAT
file 'card1.mov'
file 'card2.mov'
file 'recording_scaled.mov'
file 'card3.mov'
file 'card4.mov'
CONCAT

# Concat video segments
ffmpeg -y -f concat -safe 0 -i "$OUT/filelist.txt" \
  -c:v libx264 -preset fast -pix_fmt yuv420p \
  "$OUT/video_only.mov" 2>/dev/null

# Add music
ffmpeg -y -i "$OUT/video_only.mov" -i "$OUT/music.m4a" \
  -c:v copy -c:a aac -shortest -t 60 \
  "$OUT/one-click-build-demo.mp4" 2>/dev/null

echo ""
echo "=== DONE ==="
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$OUT/one-click-build-demo.mp4" 2>/dev/null)
echo "Output: $OUT/one-click-build-demo.mp4"
echo "Duration: ${DURATION}s"
echo ""
echo "Open: open $OUT/one-click-build-demo.mp4"
