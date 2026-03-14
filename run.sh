#!/bin/bash
# Run Skrivar — Mac menubar speech-to-text app
# Usage: ./run.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Activate venv if it exists
if [ -d "venv" ]; then
    source venv/bin/activate
elif [ -d ".venv" ]; then
    source .venv/bin/activate
fi

# Force unbuffered output so we see prints immediately
export PYTHONUNBUFFERED=1
python -m skrivar
