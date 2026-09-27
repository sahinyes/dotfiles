#!/usr/bin/env python3
"""Read claude-pulse cache and output tmux-formatted status segment with bars."""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Nord Frost palette — matches tmux status bar theme
NORD8 = "#88C0D0"   # cyan — low usage (good)
NORD9 = "#81A1C1"   # blue — medium usage
NORD13 = "#EBCB8B"  # yellow — high usage (warning)
NORD11 = "#BF616A"  # red — critical
NORD3 = "#4C566A"   # dim — empty bar / separators
NORD4 = "#D8DEE9"   # text — labels

BAR_WIDTH = 6
FILLED = "━"
EMPTY = "─"


def color_for_pct(pct):
    if pct is None:
        return NORD3
    if pct >= 80:
        return NORD11
    if pct >= 50:
        return NORD13
    return NORD8


def make_bar(pct, color):
    filled = round(pct / 100 * BAR_WIDTH)
    empty = BAR_WIDTH - filled
    return f"#[fg={color}]{FILLED * filled}#[fg={NORD3}]{EMPTY * empty}"


def fmt_reset(resets_at):
    if not resets_at:
        return ""
    try:
        reset = datetime.fromisoformat(resets_at)
        now = datetime.now(timezone.utc)
        secs = int((reset - now).total_seconds())
        if secs <= 0:
            return ""
        if secs < 3600:
            return f"{secs // 60}m"
        h = secs // 3600
        m = (secs % 3600) // 60
        if h < 24:
            return f"{h}h{m:02d}m"
        d = h // 24
        rh = h % 24
        return f"{d}d{rh}h"
    except (ValueError, TypeError):
        return ""


def main():
    base = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    cache_path = base / "claude-status" / "cache.json"

    try:
        with open(cache_path, "r") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        print("")
        return

    if time.time() - data.get("timestamp", 0) > 300:
        print("")
        return

    usage = data.get("usage", {})
    plan = data.get("plan", "")
    parts = []

    # Session (5-hour)
    five = usage.get("five_hour")
    if five and five.get("utilization") is not None:
        pct = five["utilization"]
        c = color_for_pct(pct)
        bar = make_bar(pct, c)
        reset = fmt_reset(five.get("resets_at"))
        r = f" {reset}" if reset else ""
        parts.append(f"#[fg={NORD4}]S {bar} #[fg={c}]{pct:.0f}%{r}")

    # Weekly (7-day)
    seven = usage.get("seven_day")
    if seven and seven.get("utilization") is not None:
        pct = seven["utilization"]
        c = color_for_pct(pct)
        bar = make_bar(pct, c)
        reset = fmt_reset(seven.get("resets_at"))
        r = f" {reset}" if reset else ""
        parts.append(f"#[fg={NORD4}]W {bar} #[fg={c}]{pct:.0f}%{r}")

    # Model-specific (Opus/Sonnet)
    for key, label in [("seven_day_opus", "Op"), ("seven_day_sonnet", "So")]:
        model = usage.get(key)
        if model and model.get("utilization") is not None:
            pct = model["utilization"]
            c = color_for_pct(pct)
            bar = make_bar(pct, c)
            parts.append(f"#[fg={NORD4}]{label} {bar} #[fg={c}]{pct:.0f}%")

    # Plan
    if plan:
        parts.append(f"#[fg={NORD9}]{plan}")

    if parts:
        sep = f" #[fg={NORD3}]| "
        print(f" {sep.join(parts)}#[default] ")
    else:
        print("")


if __name__ == "__main__":
    main()
