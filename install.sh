#!/usr/bin/env bash
# One-time setup on a new Mac: ./install.sh
# Sets up Ruby 4.0, Ollama and the Granite model, then the gems and database.
# It doesn't leave Ollama running: ./run.sh starts it when you run the app.
# Homebrew is optional: it's used if installed, offered if not, and without it
# Ruby comes from mise or rbenv and Ollama from its own download.
# Safe to re-run: anything already installed is skipped.
# Afterwards, start the app with ./run.sh
set -euo pipefail
cd "$(dirname "$0")"

MODEL="${OLLAMA_MODEL:-granite4.2:8b}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
RUBY_WANTED="$(sed 's/^ruby-//' .ruby-version 2> /dev/null || echo 4.0.10)"
PROFILE="$HOME/.zprofile"

step() { echo; echo "==> $1"; }
ruby_ok() { command -v ruby > /dev/null && ruby -e 'exit(RUBY_VERSION.start_with?("4.0") ? 0 : 1)'; }
ollama_up() { curl -s --max-time 2 "$OLLAMA_URL/api/tags" > /dev/null; }
have_ollama() { command -v ollama > /dev/null || [[ -d /Applications/Ollama.app ]]; }
load_brew() {
  command -v brew > /dev/null && return 0
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$candidate" ]] && eval "$("$candidate" shellenv)" && return 0
  done
  return 1
}

# Adds a line to ~/.zprofile once, so new terminals find what was installed.
remember() {
  grep -qxF "$1" "$PROFILE" 2> /dev/null || { echo "$1" >> "$PROFILE"; echo "    Added to $PROFILE: $1"; }
}

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script is for macOS. On Linux, install Ruby 4.0 and Ollama yourself, then run:"
  echo "  ollama pull $MODEL && bundle install && bin/rails db:prepare && ./run.sh"
  exit 1
fi

step "Homebrew (optional)"
if load_brew; then
  echo "    Found: Ruby and Ollama will be installed with Homebrew if needed."
  remember "eval \"\$($(command -v brew) shellenv)\""
else
  answer=n
  if [[ -t 0 ]]; then
    read -r -p "    Homebrew is not installed. Install it? (it will ask for your password) [y/N] " answer || answer=n
  fi
  if [[ "$answer" =~ ^[Yy] ]]; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    load_brew
    remember "eval \"\$($(command -v brew) shellenv)\""
  else
    echo "    Skipped: continuing without Homebrew."
  fi
fi
use_brew() { command -v brew > /dev/null; }

step "Ruby 4.0"
if ! ruby_ok; then
  if use_brew; then
    brew list ruby > /dev/null 2>&1 || brew install ruby
    export PATH="$(brew --prefix ruby)/bin:$PATH"
    remember "export PATH=\"$(brew --prefix ruby)/bin:\$PATH\""
  elif command -v mise > /dev/null; then
    mise install "ruby@$RUBY_WANTED"
    export PATH="$(mise where "ruby@$RUBY_WANTED")/bin:$PATH"
    echo "    Installed with mise. If ./run.sh can't find Ruby 4.0, run: mise use ruby@$RUBY_WANTED"
  elif command -v rbenv > /dev/null; then
    rbenv install --skip-existing "$RUBY_WANTED"
    export PATH="$(rbenv root)/versions/$RUBY_WANTED/bin:$PATH"
    echo "    Installed with rbenv; .ruby-version in this folder selects it."
  fi
fi
if ruby_ok; then
  echo "    $(ruby -v)"
else
  echo "    Ruby 4.0 is needed, and there's no Homebrew, mise or rbenv to install it with."
  echo "    Install Ruby $RUBY_WANTED, e.g. with mise (https://mise.jdx.dev), then re-run ./install.sh"
  exit 1
fi

# Ollama is optional for the app: without it the samples use built-in fixtures.
step "Ollama"
if have_ollama; then
  echo "    Already installed."
elif use_brew; then
  brew install ollama
else
  echo "    Not installed. Download it from https://ollama.com/download, open it once, then re-run"
  echo "    ./install.sh to pull the model. Until then the samples use built-in fixtures."
fi

if have_ollama; then
  # The app ships its command-line tool inside the bundle.
  if ! command -v ollama > /dev/null && [[ -x /Applications/Ollama.app/Contents/Resources/ollama ]]; then
    export PATH="/Applications/Ollama.app/Contents/Resources:$PATH"
  fi

  # Pulling needs a running server. Serving the app is ./run.sh's job, so a
  # server started here only lasts for the pull.
  if ! ollama_up; then
    ollama serve > "${TMPDIR:-/tmp}/ollama-install.log" 2>&1 &
    PULL_SERVER=$!
    trap 'kill "$PULL_SERVER" 2> /dev/null || true' EXIT
    for _ in $(seq 1 30); do ollama_up && break; sleep 1; done
    ollama_up || { echo "    Could not start Ollama to pull the model (log: ${TMPDIR:-/tmp}/ollama-install.log)."; exit 1; }
  fi

  step "Model $MODEL"
  if ollama list | awk 'NR > 1 { print $1 }' | grep -qxF "$MODEL"; then
    echo "    Already pulled."
  else
    echo "    Downloading (several GB, this can take a while)."
    ollama pull "$MODEL"
  fi
fi

step "Gems"
bundle install --quiet

step "Database"
bin/rails db:prepare

echo
echo "All set. Start the app (and Ollama) with: ./run.sh"
echo "(Open a new terminal first if Ruby or Homebrew was just installed.)"
