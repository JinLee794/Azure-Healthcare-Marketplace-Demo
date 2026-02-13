#!/usr/bin/env python3
"""
Prior Auth Workflow Fidelity Evaluation — CLI Runner

Scans data/cases/ for assessment.json waypoints, evaluates each against
the prior-auth skill contract, and compares decisions against ground truth.

Usage:
  python scripts/eval_prior_auth.py
  python scripts/eval_prior_auth.py --cases-dir data/cases --verbose
  python scripts/eval_prior_auth.py --json  # machine-readable output
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Add project root to path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from tests.eval.prior_auth_eval import (  # noqa: E402
    CaseEvalReport,
    evaluate_all_cases,
    format_report,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate prior-auth workflow fidelity against skill contract and ground truth."
    )
    parser.add_argument(
        "--cases-dir",
        type=Path,
        default=PROJECT_ROOT / "data" / "cases",
        help="Directory containing PA case folders (default: data/cases)",
    )
    parser.add_argument(
        "--ground-truth",
        type=Path,
        default=None,
        help="Ground truth JSON path (default: <cases-dir>/ground_truth.json)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output machine-readable JSON report",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed per-case evaluation",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=50.0,
        help="Minimum average fidelity score to pass (default: 50)",
    )
    args = parser.parse_args()

    cases_dir = args.cases_dir.resolve()
    ground_truth_path = (
        args.ground_truth.resolve()
        if args.ground_truth
        else cases_dir / "ground_truth.json"
    )

    if not cases_dir.exists():
        print(f"Error: Cases directory not found: {cases_dir}", file=sys.stderr)
        return 1

    # --- Run evaluation ---
    reports = evaluate_all_cases(
        cases_dir,
        ground_truth_path if ground_truth_path.exists() else None,
    )

    if not reports:
        print("No assessment.json files found in case directories.", file=sys.stderr)
        return 1

    # --- JSON output ---
    if args.json:
        output = _reports_to_dict(reports)
        print(json.dumps(output, indent=2, default=str))
        return 0 if output["summary"]["average_fidelity"] >= args.threshold else 1

    # --- Human-readable output ---
    report_text = format_report(reports)
    print(report_text)

    if args.verbose:
        print("\n--- DETAILED ANALYSIS ---\n")
        for r in reports:
            _print_detailed(r)

    avg = sum(r.score for r in reports) / len(reports)
    if avg < args.threshold:
        print(
            f"\n⚠ BELOW THRESHOLD: Average fidelity {avg:.1f} < {args.threshold}",
            file=sys.stderr,
        )
        return 1

    return 0


def _reports_to_dict(reports: list[CaseEvalReport]) -> dict:
    """Convert reports to serializable dict."""
    cases = []
    for r in reports:
        case = {
            "case_id": r.case_id,
            "score": r.score,
            "assessment_path": r.assessment_path,
            "schema_valid": r.schema_result.valid,
            "beads": {
                b.bead_id: {
                    "present": b.present,
                    "status": b.status,
                    "ordered": b.ordered,
                    "errors": b.errors,
                }
                for b in r.bead_results
            },
        }
        if r.decision_result:
            case["decision"] = {
                "ai": r.decision_result.ai_decision,
                "ground_truth": r.decision_result.ground_truth_decision,
                "match": r.decision_result.match,
                "confidence_score": r.decision_result.confidence_score,
                "criteria_percentage": r.decision_result.criteria_percentage,
            }
        cases.append(case)

    n = len(reports)
    with_gt = [r for r in reports if r.decision_result]
    matched = sum(1 for r in with_gt if r.decision_result.match)
    avg = sum(r.score for r in reports) / n if n else 0

    return {
        "summary": {
            "cases_evaluated": n,
            "average_fidelity": round(avg, 1),
            "decision_accuracy": f"{matched}/{len(with_gt)}",
            "decision_accuracy_pct": round(matched / len(with_gt) * 100, 1) if with_gt else None,
        },
        "cases": cases,
    }


def _print_detailed(report: CaseEvalReport) -> None:
    """Print detailed analysis for a single case."""
    print(f"  Case: {report.case_id}  (score={report.score})")
    print(f"    Path: {report.assessment_path}")

    # Beads
    for b in report.bead_results:
        icon = "✓" if b.present and b.ordered else "✗"
        print(f"    {icon} {b.bead_id}: status={b.status}", end="")
        if b.errors:
            print(f"  ⚠ {b.errors}")
        else:
            print()

    # Schema
    sr = report.schema_result
    if sr.missing_top_level:
        print(f"    Schema: missing top-level={sr.missing_top_level}")
    if sr.missing_recommendation:
        print(f"    Schema: missing recommendation={sr.missing_recommendation}")

    # Decision
    if report.decision_result:
        dr = report.decision_result
        icon = "✓" if dr.match else "✗"
        print(
            f"    Decision: {icon} AI={dr.ai_decision} GT={dr.ground_truth_decision} "
            f"conf={dr.confidence_score}%"
        )

    print()


if __name__ == "__main__":
    sys.exit(main())
