"""Summarize StepUp buckets.csv without uploading or modifying sensor records.

Usage: python scripts/summarize-step-buckets.py path/to/buckets.csv
Counts include late adjustments. LIVE and REPLAY evidence stays separate.
Credit/raw is a credit ratio, not a measurement of walking accuracy.
"""

import argparse
import csv
import json
import sys
from collections import Counter


def summarize(path):
    groups = {}
    required = {"source", "raw_delta", "credited", "state"}
    with open(path, encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError("Missing CSV columns: " + ", ".join(sorted(missing)))
        for line, row in enumerate(reader, 2):
            try:
                counts = [int(row[key]) for key in ("raw_delta", "credited")]
                adjustments = [int(row.get(key) or 0) for key in
                               ("late_adjust_raw", "late_adjust_credited")]
                raw = counts[0] + adjustments[0]
                credit = counts[1] + adjustments[1]
                if min(counts + adjustments) < 0 or credit > raw:
                    raise ValueError("negative counts or credit exceeds raw")
                source = row["source"].strip()
                state = row["state"].strip()
                if not source or not state:
                    raise ValueError("source and state must be nonempty")
            except (ValueError, TypeError, AttributeError) as error:
                raise ValueError(f"Invalid bucket on CSV line {line}: {error}") from error
            group = groups.setdefault(source, {
                "buckets": 0, "raw_steps": 0, "credited_steps": 0,
                "states": Counter(), "reasons": Counter(),
            })
            group["buckets"] += 1
            group["raw_steps"] += raw
            group["credited_steps"] += credit
            group["states"][state] += 1
            if row.get("reason"):
                group["reasons"][row["reason"]] += 1
    for group in groups.values():
        group["credit_ratio"] = (group["credited_steps"] / group["raw_steps"]
                                 if group["raw_steps"] else None)
    return {"note": "Credit ratio is not accuracy; LIVE and REPLAY are separate.",
            "sources": groups}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("buckets_csv")
    args = parser.parse_args()
    try:
        result = summarize(args.buckets_csv)
    except (OSError, ValueError, csv.Error) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
