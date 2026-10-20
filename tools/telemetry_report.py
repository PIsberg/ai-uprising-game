#!/usr/bin/env python3
"""Summarise a playtest TELEMETRY session (scripts/autoload/telemetry.gd).

    python tools/telemetry_report.py                 # newest session in the Godot user dir
    python tools/telemetry_report.py <file.jsonl>    # a given session
    python tools/telemetry_report.py --all           # every session there, pooled

Per level: attempts, clears, time, deaths with their killers, the top damage
sources, shots/hits/kills per weapon, and stuck spots (pressing a move key 2 s
without moving). Then the session's top killers overall.
"""
import glob
import json
import os
import sys
from collections import Counter, defaultdict


def user_dir():
    if sys.platform == "win32":
        base = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata")
    elif sys.platform == "darwin":
        base = os.path.expanduser("~/Library/Application Support/Godot/app_userdata")
    else:
        base = os.path.expanduser("~/.local/share/godot/app_userdata")
    return os.path.join(base, "AI Uprising", "telemetry")


def load(paths):
    events = []
    for p in paths:
        with open(p, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    events.append(json.loads(line))
                except json.JSONDecodeError:
                    print(f"{p}:{n}: not JSON, skipped", file=sys.stderr)
    return events


def main(argv):
    if len(argv) > 1 and argv[1] != "--all":
        paths = [argv[1]]
    else:
        files = sorted(glob.glob(os.path.join(user_dir(), "*.jsonl")))
        if not files:
            print(f"no sessions in {user_dir()}")
            return 1
        paths = files if "--all" in argv else files[-1:]
    events = load(paths)
    levels = defaultdict(lambda: {"starts": 0, "ends": Counter(), "time": 0.0, "deaths": [],
                                  "taken": Counter(), "shots": Counter(), "hits": Counter(),
                                  "kills": Counter(), "stuck": [], "grades": [], "breaches": Counter()})
    killers = Counter()
    for e in events:
        lvl = e.get("level")
        if lvl is None:
            continue
        L = levels[lvl]
        kind = e.get("event")
        if kind == "level_start":
            L["starts"] += 1
        elif kind == "death":
            L["deaths"].append(e)
            killers[e.get("killer") or "UNKNOWN"] += 1
        elif kind == "breach":
            L["breaches"][e.get("label", "?")] += 1
        elif kind == "stuck":
            L["stuck"].append(e.get("pos"))
        elif kind == "level_end":
            L["ends"][e.get("result", "?")] += 1
            L["time"] += float(e.get("time", 0.0))
            if e.get("grade"):
                L["grades"].append(e["grade"])
            for k, c in (("damage_taken", "taken"), ("shots_by_weapon", "shots"),
                         ("hits_by_weapon", "hits"), ("kills_by_weapon", "kills")):
                for name, v in (e.get(k) or {}).items():
                    L[c][name] += float(v)
    print(f"{len(paths)} session(s), {len(events)} events")
    for lvl, L in levels.items():
        ends = ", ".join(f"{n} {r}" for r, n in L["ends"].items()) or "none"
        print(f"\n== {lvl}: {L['starts']} start(s), ends: {ends}, {L['time'] / 60:.1f} min played"
              + (f", grades {' '.join(L['grades'])}" if L["grades"] else ""))
        if L["deaths"]:
            by = Counter(d.get("killer") or "UNKNOWN" for d in L["deaths"])
            print(f"   deaths {len(L['deaths'])}: " + ", ".join(f"{k} x{n}" for k, n in by.most_common()))
        if L["taken"]:
            total = sum(L["taken"].values())
            print("   damage taken: " + ", ".join(f"{k} {v:.0f} ({100 * v / total:.0f}%)" for k, v in L["taken"].most_common(5)))
        guns = set(L["shots"]) | set(L["kills"])
        for g in sorted(guns, key=lambda g: -L["shots"][g]):
            s, h, k = L["shots"][g], L["hits"][g], L["kills"][g]
            acc = f", {100 * h / s:.0f}% hit" if s else ""
            print(f"   {g}: {s:.0f} shots{acc}, {k:.0f} kills")
        if L["breaches"]:
            print("   breaches: " + ", ".join(f"{k} x{n}" for k, n in L["breaches"].most_common()))
        for p in L["stuck"]:
            print(f"   stuck at {p}")
    if killers:
        print("\nTop killers: " + ", ".join(f"{k} x{n}" for k, n in killers.most_common(8)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
