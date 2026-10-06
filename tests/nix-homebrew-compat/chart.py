#!/usr/bin/env python3
"""Render the nix-homebrew compatibility history as an SVG line chart."""

import argparse
import json
from datetime import datetime
from pathlib import Path


WIDTH = 1000
HEIGHT = 540
PLOT_X = 78
PLOT_Y = 118
PLOT_W = 880
PLOT_H = 332

FONT = "-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif"
SERIES = (
    ("total", "Total", "#2563eb"),
    ("pass", "Pass", "#16a34a"),
    ("fail", "Fail", "#dc2626"),
    ("error", "Error", "#f59e0b"),
    ("skip", "Skip", "#7c3aed"),
)
# Bands sit between absolute series, top to bottom.
BANDS = (
    ("total", "pass", "#bfdbfe"),
    ("pass", "fail", "#6ee7b7"),
    ("fail", "error", "#e5e7eb"),
    ("error", "skip", "#ffedd5"),
    ("skip", None, "#ede9fe"),
)


def nice_max(peak: int) -> int:
    if peak <= 0:
        return 10
    magnitude = 10 ** len(str(peak - 1)) // 10 or 1
    for step in (1, 2, 5, 10):
        size = step * magnitude
        ceiling = ((peak + size - 1) // size) * size
        if ceiling >= peak + max(1, peak // 20):
            return ceiling
    return peak + magnitude


def pct(part: int, total: int) -> str:
    if total == 0:
        return "0.0%"
    scaled = (part * 1000 + total // 2) // total
    return f"{scaled // 10}.{scaled % 10}%"


def x_of(index: int, count: int) -> float:
    # Leave a shelf after the last sample so the newest value is a horizontal run.
    left = PLOT_X + PLOT_W * 0.03
    right = PLOT_X + PLOT_W * 0.72
    if count == 1:
        return (left + right) / 2
    return left + (right - left) * index / (count - 1)


def y_of(value: float, y_max: int) -> float:
    return PLOT_Y + PLOT_H - (value / y_max) * PLOT_H


def step_points(points):
    """Hold each measured value until the next sample, then step.

    The first value starts at the y-axis and the last value runs to the right edge,
    so a change is a horizontal step instead of a diagonal interpolation.
    """
    if not points:
        return []
    x_left = PLOT_X
    x_right = PLOT_X + PLOT_W
    first_x, first_y = points[0]
    stepped = []
    if first_x > x_left + 0.5:
        stepped.append((x_left, first_y))
    stepped.append((first_x, first_y))
    for x, y in points[1:]:
        stepped.append((x, stepped[-1][1]))
        stepped.append((x, y))
    if x_right > stepped[-1][0] + 0.5:
        stepped.append((x_right, stepped[-1][1]))
    return stepped


def band(points_hi, points_lo, color: str) -> str:
    hi = step_points(points_hi)
    lo = step_points(points_lo)
    forward = " L ".join(f"{x:.1f},{y:.1f}" for x, y in hi)
    backward = " L ".join(f"{x:.1f},{y:.1f}" for x, y in reversed(lo))
    return f'<path d="M {forward} L {backward} Z" fill="{color}" fill-opacity="0.9"/>'


def line(points, color: str) -> str:
    coords = " ".join(f"{x:.1f},{y:.1f}" for x, y in step_points(points))
    return (
        f'<polyline points="{coords}" fill="none" stroke="{color}" '
        'stroke-width="2.25" stroke-linejoin="miter" stroke-linecap="butt"/>'
    )


def chart_point(point: dict) -> dict:
    # Unsupported checks are failures. They are not skips.
    return {
        "date": point["date"],
        "label": point.get("label") or "",
        "total": point["total"],
        "pass": point["pass"],
        "fail": point.get("fail", 0) + point.get("gap", 0),
        "error": point.get("error", 0),
        "skip": point.get("skip", 0),
    }


def render(series: list[dict]) -> str:
    series = [chart_point(point) for point in series]
    y_max = nice_max(max(point["total"] for point in series))
    count = len(series)

    def points_for(key: str | None):
        if key is None:
            return [(x_of(index, count), y_of(0, y_max)) for index in range(count)]
        return [
            (x_of(index, count), y_of(point[key], y_max))
            for index, point in enumerate(series)
        ]

    areas = []
    for upper, lower, color in BANDS:
        hi = points_for(upper)
        lo = points_for(lower)
        if any(abs(a[1] - b[1]) > 0.5 for a, b in zip(hi, lo)):
            areas.append(band(hi, lo, color))
    lines = [line(points_for(key), stroke) for key, _label, stroke in SERIES]

    grid = []
    ticks = 5
    for step in range(ticks + 1):
        value = y_max * step // ticks
        y = y_of(value, y_max)
        grid.append(
            f'<line x1="{PLOT_X}" y1="{y:.1f}" x2="{PLOT_X + PLOT_W}" y2="{y:.1f}" stroke="#e5e7eb"/>'
        )
        grid.append(
            f'<text x="{PLOT_X - 10}" y="{y + 4:.1f}" text-anchor="end" '
            f'fill="#6b7280" font-family="{FONT}" font-size="12">{value}</text>'
        )

    x_labels = []
    for index, point in enumerate(series):
        x = x_of(index, count)
        when = datetime.strptime(point["date"], "%Y-%m-%d")
        x_labels.append(
            f'<text x="{x:.1f}" y="{PLOT_Y + PLOT_H + 22}" text-anchor="middle" '
            f'fill="#6b7280" font-family="{FONT}" font-size="12">{when.strftime("%b %Y")}</text>'
        )
        label = point.get("label") or ""
        if label:
            x_labels.append(
                f'<text x="{x:.1f}" y="{PLOT_Y + PLOT_H + 38}" text-anchor="middle" '
                f'fill="#9ca3af" font-family="{FONT}" font-size="11">{escape(label)}</text>'
            )

    legend_items = []
    legend_x = PLOT_X + 16
    legend_y = PLOT_Y + 22
    cursor = legend_x + 12
    for _key, label, stroke in SERIES:
        legend_items.append(
            f'<line x1="{cursor}" y1="{legend_y}" x2="{cursor + 22}" y2="{legend_y}" '
            f'stroke="{stroke}" stroke-width="2.25" stroke-linecap="round"/>'
        )
        cursor += 28
        legend_items.append(
            f'<text x="{cursor}" y="{legend_y + 4}" fill="#374151" '
            f'font-family="{FONT}" font-size="13">{label}</text>'
        )
        cursor += 8 + len(label) * 7.4
    legend_width = cursor - legend_x + 16
    legend = (
        f'<rect x="{legend_x - 8}" y="{legend_y - 16}" width="{legend_width:.0f}" height="30" '
        f'rx="8" fill="#ffffff" stroke="#e5e7eb"/>'
        + "".join(legend_items)
    )

    last = series[-1]
    box_x = 760
    box_y = 16
    latest = f"""
    <rect x="{box_x + 2}" y="{box_y + 2}" width="220" height="90" rx="8" fill="#f3f4f6"/>
    <rect x="{box_x}" y="{box_y}" width="220" height="90" rx="8" fill="#ffffff" stroke="#d1d5db"/>
    <text x="{box_x + 14}" y="{box_y + 22}" fill="#111827" font-family="{FONT}" font-size="13" font-weight="700">Latest Results:</text>
    <text x="{box_x + 14}" y="{box_y + 42}" fill="#16a34a" font-family="{FONT}" font-size="13">Pass: {pct(last["pass"], last["total"])}</text>
    <text x="{box_x + 14}" y="{box_y + 60}" fill="#dc2626" font-family="{FONT}" font-size="13">Fail: {pct(last["fail"], last["total"])}</text>
    <text x="{box_x + 14}" y="{box_y + 78}" fill="#7c3aed" font-family="{FONT}" font-size="13">Skip: {pct(last["skip"], last["total"])}</text>
    """

    title = "nix-zerobrew — nix-homebrew Compatibility"
    subtitle = "Tracking test results over time to measure progress and compatibility"
    summary = (
        f'{last["pass"]}/{last["total"]} passing ({pct(last["pass"], last["total"])})'
    )
    axis_title_y = PLOT_Y + PLOT_H / 2

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-label="{escape(title)}: {escape(summary)}">
  <rect width="{WIDTH}" height="{HEIGHT}" fill="#ffffff"/>
  <text x="430" y="36" text-anchor="middle" fill="#111827" font-family="{FONT}" font-size="22" font-weight="700">{escape(title)}</text>
  <text x="430" y="58" text-anchor="middle" fill="#6b7280" font-family="{FONT}" font-size="13" font-style="italic">{escape(subtitle)}</text>
  {latest}
  <line x1="{PLOT_X}" y1="{PLOT_Y}" x2="{PLOT_X}" y2="{PLOT_Y + PLOT_H}" stroke="#d1d5db"/>
  <line x1="{PLOT_X}" y1="{PLOT_Y + PLOT_H}" x2="{PLOT_X + PLOT_W}" y2="{PLOT_Y + PLOT_H}" stroke="#d1d5db"/>
  {''.join(grid)}
  <text transform="translate(20,{axis_title_y:.1f}) rotate(-90)" text-anchor="middle" fill="#374151" font-family="{FONT}" font-size="13">Number of Tests</text>
  {''.join(areas)}
  {''.join(lines)}
  {legend}
  {''.join(x_labels)}
  <text x="{PLOT_X + PLOT_W / 2:.1f}" y="{PLOT_Y + PLOT_H + 62}" text-anchor="middle" fill="#374151" font-family="{FONT}" font-size="13">Date</text>
</svg>
"""


def escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--history", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--stale", required=True)
    parser.add_argument("--pass-count", required=True, type=int)
    parser.add_argument("--gap-count", required=True, type=int)
    parser.add_argument("--fail-count", required=True, type=int)
    parser.add_argument("--total-count", required=True, type=int)
    args = parser.parse_args()

    history = json.loads(Path(args.history).read_text())
    series = history["series"]
    if not series:
        raise SystemExit("compatibility history has no points")
    last = series[-1]
    current = {
        "pass": args.pass_count,
        "gap": args.gap_count,
        "fail": args.fail_count,
        "total": args.total_count,
    }
    Path(args.summary).write_text(json.dumps(current) + "\n")
    stale_path = Path(args.stale)
    matches = all(last[key] == current[key] for key in current)
    if matches:
        stale_path.unlink(missing_ok=True)
    else:
        stale_path.write_text(
            "docs/compatibility-history.json does not end with the current suite "
            f"({current['pass']} pass, {current['gap']} gap, {current['fail']} fail, "
            f"{current['total']} total).\n"
            "Refresh it with scripts/update-compatibility-graph.sh\n"
        )
    Path(args.out).write_text(render(series))


if __name__ == "__main__":
    main()
