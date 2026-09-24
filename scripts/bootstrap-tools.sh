#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Jory Shilmover
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m venv build/tools
build/tools/bin/pip install cmake==3.31.6 ninja==1.11.1.3
