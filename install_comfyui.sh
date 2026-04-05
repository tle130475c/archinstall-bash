#!/usr/bin/env bash

set -euo pipefail

uv venv --python 3.13
source .venv/bin/activate
uv pip install --pre torch torchvision torchaudio --index-url https://rocm.nightlies.amd.com/v2/gfx1151/
uv pip install -r requirements.txt
