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
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${OLLAMA_MODEL:-granite4.2:8b}"
ollama_up() { curl -s --max-time 2 "$OLLAMA_URL/api/tags" > /dev/null; }
# The Ollama app ships its command-line tool inside the bundle.
if ! command -v ollama > /dev/null && [[ -x /Applications/Ollama.app/Contents/Resources/ollama ]]; then
  export PATH="/Applications/Ollama.app/Contents/Resources:$PATH"
fi

if ! ollama_up; then
  if [[ -d /Applications/Ollama.app ]]; then
    echo "    Starting the Ollama app"
    open -a Ollama
  elif command -v ollama > /dev/null; then
    # Served only while the app runs: stopped again on Ctrl+C.
    echo "    Starting ollama serve (log: log/ollama.log)"
    mkdir -p log
    ollama serve > log/ollama.log 2>&1 &
    OLLAMA_PID=$!
    trap 'kill "$OLLAMA_PID" 2> /dev/null || true' EXIT
  fi
  for _ in $(seq 1 15); do ollama_up && break; sleep 1; done
fi

if ollama_up; then
  if curl -s --max-time 2 "$OLLAMA_URL/api/tags" | grep -qF "\"$MODEL\""; then
    echo "    Ollama is running with $MODEL: live extraction will be used."
  else
    echo "    Ollama is running, but $MODEL isn't pulled (run ./install.sh): extraction will fail and the samples use built-in fixtures."
  fi
else
  echo "    Ollama is not reachable: the three samples will use built-in fixtures."
fi

echo "==> Starting the app at $URL (press Ctrl+C to stop)"
( sleep 3 && open "$URL" ) &
bin/rails server -p "$PORT"
