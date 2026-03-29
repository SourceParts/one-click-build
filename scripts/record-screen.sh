#!/bin/bash
# Record the screen for the Parts Build demo
# Press Ctrl+C to stop recording, or it auto-stops at 70 seconds.

set -e
OUT="$HOME/Desktop/build-video"
mkdir -p "$OUT"

echo "Recording screen in 3 seconds... (Ctrl+C to stop)"
echo "Make sure Parts Build app is visible and ready."
sleep 3

echo "RECORDING..."
ffmpeg -y -f avfoundation -framerate 30 -capture_cursor 1 -i "1:none" \
  -t 70 -c:v libx264 -pix_fmt yuv420p -preset ultrafast \
  "$OUT/build_raw.mov" 2>/dev/null

echo "Recording saved: $OUT/build_raw.mov"
echo "Now run: ./scripts/generate-video.sh"
