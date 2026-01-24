#!/bin/bash
# Watch cache refresh progress in real-time
# Usage: ./scripts/watch-cache-progress.sh

JELLYFIN_HOST="${1:-localhost}"

echo "📊 Watching cache refresh progress..."
echo "Press Ctrl+C to stop"
echo ""

sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no root@$JELLYFIN_HOST "docker logs jellyfin -f 2>&1" | grep --line-buffered -i "SeriesCacheService\|cache refresh\|Processing category\|Processing series\|Cache refresh completed\|Failed to cache"
