#!/usr/bin/env python3
"""Fase 4 coverage gate input: summarize JaCoCo XML (Android) and lcov.info
(Flutter) into a Markdown table. Report-only: exits 0 always (thresholds are
a later step once baselines exist). Never silent: missing files are reported.
Usage: coverage_report.py [--jacoco FILE] [--lcov FILE]
"""
import argparse
import sys
import xml.etree.ElementTree as ET


def parse_jacoco(path):
    """Return (files, total_covered, total_missed, br_covered, br_missed)."""
    try:
        root = ET.parse(path).getroot()
    except FileNotFoundError:
        return None, "report not found: %s" % path
    except ET.ParseError as e:
        return None, "unparseable XML %s: %s" % (path, e)
    files = []
    for sf in root.iter("sourcefile"):
        name = sf.get("name", "?")
        cov = mis = bcov = bmis = 0
        for c in sf.iter("counter"):
            if c.get("type") == "LINE":
                mis += int(c.get("missed", 0))
                cov += int(c.get("covered", 0))
            elif c.get("type") == "BRANCH":
                bmis += int(c.get("missed", 0))
                bcov += int(c.get("covered", 0))
        files.append((name, cov, mis, bcov, bmis))
    return files, None


def parse_lcov(path):
    """Return (files, total_covered, total_missed, br_covered, br_missed)."""
    try:
        lines = open(path, errors="replace").read().splitlines()
    except FileNotFoundError:
        return None, "report not found: %s" % path
    files = []
    cur = None
    cov = mis = bcov = bmis = 0
    for ln in lines + ["end_of_record"]:
        if ln.startswith("SF:"):
            cur = ln[3:].split("/")[-1]
            cov = mis = bcov = bmis = 0
        elif ln.startswith("DA:"):
            try:
                hits = int(ln.split(",")[1])
            except (IndexError, ValueError):
                hits = 0
            if hits > 0:
                cov += 1
            else:
                mis += 1
        elif ln.startswith("BRDA:"):
            parts = ln.split(",")
            taken = parts[3] if len(parts) > 3 else "-"
            if taken == "-":
                bmis += 1
            else:
                bcov += 1
        elif ln == "end_of_record" and cur is not None:
            files.append((cur, cov, mis, bcov, bmis))
            cur = None
    return files, None


def pct(cov, mis):
    tot = cov + mis
    return 100.0 * cov / tot if tot else 100.0


def table(title, files):
    out = ["### %s" % title, "",
           "| File | Lines | Branches |", "| --- | --- | --- |"]
    tcov = tmis = tbc = tbm = 0
    for name, cov, mis, bcov, bmis in sorted(files):
        tcov += cov
        tmis += mis
        tbc += bcov
        tbm += bmis
        out.append("| %s | %.1f%% (%d/%d) | %.1f%% (%d/%d) |" % (
            name, pct(cov, mis), cov, cov + mis,
            pct(bcov, bmis), bcov, bcov + bmis))
    out.insert(3, "| **TOTAL** | **%.1f%% (%d/%d)** | **%.1f%% (%d/%d)** |" % (
        pct(tcov, tmis), tcov, tcov + tmis,
        pct(tbc, tbm), tbc, tbc + tbm))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--jacoco", default=None)
    ap.add_argument("--lcov", default=None)
    ap.add_argument("--label", default="Coverage report")
    args = ap.parse_args()

    print("## %s" % args.label)
    print("")
    ok = True
    if args.jacoco:
        files, err = parse_jacoco(args.jacoco)
        if err:
            print("- Android (JaCoCo): %s" % err)
            ok = False
        elif not files:
            print("- Android (JaCoCo): no source files in report")
            ok = False
        else:
            print(table("Android (JaCoCo)", files))
            print("")
    if args.lcov:
        files, err = parse_lcov(args.lcov)
        if err:
            print("- Flutter (lcov): %s" % err)
            ok = False
        elif not files:
            print("- Flutter (lcov): no source files in report")
            ok = False
        else:
            print(table("Flutter (lcov)", files))
            print("")
    if not args.jacoco and not args.lcov:
        print("No reports given.")
        ok = False
    return 0  # report-only gate: never fail the build (thresholds later)


if __name__ == "__main__":
    sys.exit(main())
