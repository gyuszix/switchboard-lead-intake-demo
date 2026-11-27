#!/usr/bin/env bash
# One-time setup on a new Mac: ./install.sh
# Installs Homebrew (if missing), Ruby 4.0, Ollama and the Granite model, then
# the gems and database. Safe to re-run: anything already installed is skipped.
# Afterwards, start the app with ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

MODEL="${OLLAMA_MODEL:-granite4.2:8b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
PROFILE="$HOME/.zprofile"

step() { echo; echo "==> $1"; }
ruby_ok() { command -v ruby > /dev/null && ruby -e 'exit(RUBY_VERSION.start_with?("4.0") ? 0 : 1)'; }
ollama_up() { curl -s --max-time 2 "$OLLAMA_URL/api/tags" > /dev/null; }

# Adds a line to ~/.zprofile once, so new terminals find Homebrew and its Ruby.
remember() {
  grep -qxF "$1" "$PROFILE" 2> /dev/null || { echo "$1" >> "$PROFILE"; echo "    Added to $PROFILE: $1"; }
}

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is for macOS. On Linux, install Ruby 4.0 and Ollama yourself, then run:"
  echo "  ollama pull $MODEL && bundle install && bin/rails db:prepare && ./run.sh"
  exit 1
fi

step "Homebrew"
if ! command -v brew > /dev/null; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$candidate" ]] && eval "$("$candidate" shellenv)" && break
  done
fi
if command -v brew > /dev/null; then
  echo "    Already installed."
else
  echo "    Installing Homebrew (it will ask for your password)."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$candidate" ]] && eval "$("$candidate" shellenv)" && break
  done
fi
remember "eval \"\$($(command -v brew) shellenv)\""

step "Ruby 4.0"
if ! ruby_ok; then
  brew list ruby > /dev/null 2>&1 || brew install ruby
  export PATH="$(brew --prefix ruby)/bin:$PATH"
  remember "export PATH=\"$(brew --prefix ruby)/bin:\$PATH\""
fi
if ruby_ok; then
  echo "    $(ruby -v)"
else
  echo "    Homebrew's Ruby is $(ruby -e 'print RUBY_VERSION'), but this app needs 4.0."
  echo "    Install Ruby $(cat .ruby-version 2> /dev/null || echo 4.0) with a version manager (e.g. mise or rbenv), then re-run."
  exit 1
fi

step "Ollama"
if command -v ollama > /dev/null; then
  echo "    Already installed."
else
  brew install ollama
fi

step "Serving Ollama"
if ollama_up; then
  echo "    Already running at $OLLAMA_URL."
else
  # Runs Ollama in the background now and at every login.
  brew services start ollama
  for _ in $(seq 1 30); do ollama_up && break; sleep 1; done
  ollama_up || { echo "    Ollama did not start. Try 'ollama serve' in another terminal, then re-run."; exit 1; }
  echo "    Running at $OLLAMA_URL."
fi

step "Model $MODEL"
if ollama list | awk 'NR > 1 { print $1 }' | grep -qxF "$MODEL"; then
  echo "    Already pulled."
else
  echo "    Downloading (several GB, this can take a while)."
  ollama pull "$MODEL"
fi

step "Gems"
bundle install --quiet

step "Database"
bin/rails db:prepare

echo
echo "All set. Start the app with: ./run.sh"
echo "(Open a new terminal first if Ruby or Homebrew was just installed.)"
