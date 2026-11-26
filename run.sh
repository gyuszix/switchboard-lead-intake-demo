#!/usr/bin/env bash
# One command to run the app: ./run.sh
set -e
cd "$(dirname "$0")"

PORT=3000
URL="http://localhost:$PORT"

echo "==> Installing gems (first run only takes a while)"
bundle install --quiet

echo "==> Setting up the database"
bin/rails db:prepare

echo "==> Checking Ollama"
if curl -s --max-time 2 "${OLLAMA_URL:-http://localhost:11434}/api/tags" > /dev/null; then
  echo "    Ollama is running: live extraction will be used."
else
  echo "    Ollama is not reachable: the three samples will use built-in fixtures."
fi

echo "==> Starting the app at $URL (press Ctrl+C to stop)"
( sleep 3 && open "$URL" ) &
exec bin/rails server -p "$PORT"
