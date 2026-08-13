#!/usr/bin/env python3
"""Measure structure-recovery signals in normalizer comparison artifacts."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*$")
TABLE_ROW = re.compile(r"^\s*\|.*\|\s*$")


def normalize(value: str) -> str:
    value = re.sub(r"[*_`]", "", value)
    value = re.sub(r"\s+#+\s*$", "", value)
    return " ".join(value.split()).casefold()


def lcs_length(left: list[str], right: list[str]) -> int:
    previous = [0] * (len(right) + 1)
    for left_item in left:
        current = [0]
        for index, right_item in enumerate(right, start=1):
            if left_item == right_item:
                current.append(previous[index - 1] + 1)
            else:
                current.append(max(current[-1], previous[index]))
        previous = current
    return previous[-1]


def read_exit_code(candidate_directory: Path) -> int | None:
    path = candidate_directory / "exit-code"
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except ValueError:
        return None


def read_duration(candidate_directory: Path) -> int | None:
    path = candidate_directory / "duration-ms"
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="utf-8").strip())
    except ValueError:
        return None


def inspect_candidate(
    candidate_directory: Path, expected: dict[str, Any]
) -> dict[str, Any]:
    document_path = candidate_directory / "document.md"
    document_available = document_path.is_file()
    markdown = (
        document_path.read_text(encoding="utf-8", errors="replace")
        if document_available
        else ""
    )
    headings = [
        {"level": len(match.group(1)), "text": " ".join(match.group(2).split())}
        for line in markdown.splitlines()
        if (match := HEADING.match(line))
    ]
    actual_headings = [normalize(heading["text"]) for heading in headings]
    expected_headings = [normalize(heading) for heading in expected["headings"]]
    actual_heading_set = set(actual_headings)
    missing_headings = [
        heading
        for heading, normalized in zip(expected["headings"], expected_headings)
        if normalized not in actual_heading_set
    ]
    marker_positions = [markdown.find(marker) for marker in expected["ordered_markers"]]
    table_cells_present = [cell for cell in expected["table_cells"] if cell in markdown]

    return {
        "exit_code": read_exit_code(candidate_directory),
        "duration_ms": read_duration(candidate_directory),
        "document_available": document_available,
        "content_bytes": len(markdown.encode("utf-8")),
        "heading_count": len(headings),
        "headings": headings,
        "heading_coverage": {
            "found": len(expected_headings) - len(missing_headings),
            "expected": len(expected_headings),
        },
        "heading_order_lcs": {
            "found": lcs_length(expected_headings, actual_headings),
            "expected": len(expected_headings),
        },
        "missing_headings": missing_headings,
        "ordered_markers_present": sum(position >= 0 for position in marker_positions),
        "ordered_markers_expected": len(marker_positions),
        "reading_order_ok": all(position >= 0 for position in marker_positions)
        and marker_positions == sorted(marker_positions),
        "table_cell_coverage": {
            "found": len(table_cells_present),
            "expected": len(expected["table_cells"]),
        },
        "missing_table_cells": [
            cell for cell in expected["table_cells"] if cell not in markdown
        ],
        "markdown_table_row_count": sum(
            bool(TABLE_ROW.match(line)) for line in markdown.splitlines()
        ),
        "furniture_occurrences": sum(
            markdown.count(item) for item in expected["furniture"]
        ),
    }


def ratio(metric: dict[str, int]) -> str:
    return f"{metric['found']}/{metric['expected']}"


def render_report(summary: dict[str, Any]) -> str:
    lines = [
        "# Normalizer structure comparison",
        "",
        "The measurements below are deterministic signals from the controlled fixture; "
        "they are not a universal quality or performance benchmark.",
        "",
        "| Candidate | Exit | Time | Headings | Heading order | Markers | Reading order | Table cells | Markdown table rows | Furniture leaks |",
        "|---|---:|---:|---:|---:|---:|:---:|---:|---:|---:|",
    ]
    for name, result in summary["candidates"].items():
        exit_code = "missing" if result["exit_code"] is None else str(result["exit_code"])
        duration = (
            "missing"
            if result["duration_ms"] is None
            else f"{result['duration_ms'] / 1000:.2f}s"
        )
        markers = (
            f"{result['ordered_markers_present']}/"
            f"{result['ordered_markers_expected']}"
        )
        lines.append(
            f"| [{name}]({name}/document.md) | {exit_code} | {duration} | "
            f"{ratio(result['heading_coverage'])} | "
            f"{ratio(result['heading_order_lcs'])} | {markers} | "
            f"{'yes' if result['reading_order_ok'] else 'no'} | "
            f"{ratio(result['table_cell_coverage'])} | "
            f"{result['markdown_table_row_count']} | "
            f"{result['furniture_occurrences']} |"
        )

    lines.extend(["", "## Missing expected structure", ""])
    for name, result in summary["candidates"].items():
        missing_headings = result["missing_headings"]
        missing_cells = result["missing_table_cells"]
        lines.append(f"### {name}")
        lines.append("")
        lines.append(
            "Missing headings: "
            + (", ".join(f"`{item}`" for item in missing_headings) or "none")
            + "."
        )
        lines.append(
            "Missing table cells: "
            + (", ".join(f"`{item}`" for item in missing_cells) or "none")
            + "."
        )
        lines.append("")

    lines.extend(
        [
            "## Artifacts",
            "",
            "- [`summary.json`](summary.json) contains all measurements and extracted headings.",
            "- [`environment.json`](environment.json) records the tool versions used by this run.",
            "- Each candidate directory retains stdout, stderr, exit status, Markdown, and structured output when available.",
            "",
        ]
    )
    return "\n".join(lines)


def candidate(value: str) -> tuple[str, Path]:
    try:
        name, path = value.split("=", 1)
    except ValueError as error:
        raise argparse.ArgumentTypeError("candidate must be NAME=PATH") from error
    if not name or not path:
        raise argparse.ArgumentTypeError("candidate must be NAME=PATH")
    return name, Path(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--output-directory", required=True, type=Path)
    parser.add_argument("--candidate", action="append", required=True, type=candidate)
    arguments = parser.parse_args()

    expected = json.loads(arguments.expected.read_text(encoding="utf-8"))
    candidates = {
        name: inspect_candidate(path, expected) for name, path in arguments.candidate
    }
    summary = {
        "schema": "sandwalk.normalizer-comparison.v1",
        "expected": str(arguments.expected),
        "candidates": candidates,
    }
    output_directory = arguments.output_directory
    output_directory.mkdir(parents=True, exist_ok=True)
    (output_directory / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (output_directory / "report.md").write_text(
        render_report(summary), encoding="utf-8"
    )
    if not all(result["document_available"] for result in candidates.values()):
        raise SystemExit("comparison incomplete: one or more candidates produced no document")


if __name__ == "__main__":
    main()
