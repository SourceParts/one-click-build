#!/bin/bash
# Automated demo recording using AppleScript + ffmpeg
# Records the Parts Build app window, clicks Build, captures the pipeline run
set -e

OUT="$HOME/Desktop/build-video"
mkdir -p "$OUT"

APP_NAME="Build"

echo "=== Starting Parts Build if not running ==="
open ~/Work/SourceParts/one-click-build/Build.app 2>/dev/null || true
sleep 2

echo "=== Bringing window to front ==="
osascript -e "
tell application \"System Events\"
    tell process \"$APP_NAME\"
        set frontmost to true
    end tell
end tell
"
sleep 1

echo "=== Getting window bounds ==="
# Get the window position and size for cropping
BOUNDS=$(osascript -e "
tell application \"System Events\"
    tell process \"$APP_NAME\"
        set win to window 1
        set pos to position of win
        set sz to size of win
        return (item 1 of pos as text) & \",\" & (item 2 of pos as text) & \",\" & (item 1 of sz as text) & \",\" & (item 2 of sz as text)
    end tell
end tell
")
echo "Window bounds: $BOUNDS"

# Parse bounds
IFS=',' read -r WX WY WW WH <<< "$BOUNDS"
echo "Position: ${WX}x${WY}, Size: ${WW}x${WH}"

echo "=== Starting screen recording in 2 seconds ==="
sleep 2

# Start ffmpeg recording the full screen
ffmpeg -y -f avfoundation -framerate 30 -capture_cursor 1 -i "1:none" \
  -t 90 -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  "$OUT/build_raw.mov" &
FFMPEG_PID=$!

sleep 2

echo "=== Clicking Build button via AppleScript ==="
osascript -e "
tell application \"System Events\"
    tell process \"$APP_NAME\"
        -- Click roughly in the center of the Build button area
        -- The button is full-width, roughly 150px from top
        set win to window 1
        set pos to position of win
        set sz to size of win
        set clickX to (item 1 of pos) + ((item 1 of sz) / 2)
        set clickY to (item 2 of pos) + 180
        click at {clickX, clickY}
    end tell
end tell
" 2>/dev/null || echo "(Click may need accessibility permissions)"

echo "=== Recording... waiting for pipeline to finish ==="
echo "Press Ctrl+C to stop early, or wait 90 seconds"

# Wait for the recording to finish
wait $FFMPEG_PID 2>/dev/null || true

echo "=== Recording saved: $OUT/build_raw.mov ==="
echo "Now run: ./scripts/generate-video.sh"
