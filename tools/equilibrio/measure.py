#!/usr/bin/env python3
"""Medidas de la pasada de equilibrio (rama equilibrio): full_player y pacing antes/después de cada punto.

  python3 tools/equilibrio/measure.py full  --root <worktree> --tag <nombre> [--seeds 1,2,3,4] [--years 3] [--jobs 2]
  python3 tools/equilibrio/measure.py pacing --root <worktree> --tag <nombre> [--seeds 5] [--fl]
  python3 tools/equilibrio/measure.py sum   --root <worktree> --tag <nombre>         # resume reports/full_player_<tag>
  python3 tools/equilibrio/measure.py diff  reports/equilibrio/a.json reports/equilibrio/b.json

Escribe un resumen pequeño en reports/equilibrio/<tag>.json (sin partidas guardadas).
"""
import json, os, statistics, subprocess, sys

GODOT = "/opt/homebrew/bin/godot"
KEYS = ["debt_paid_day", "title_citizen_day", "wedding_day", "had_child", "net_year_1", "net_year_2", "net_year_3",
        "gold_end", "gold_min", "mechanics_used", "refused_orders", "ledger_mismatch", "engine_errors", "stalls",
        "unlocks_off", "gap_max_s", "gap_median_s", "y1_gap_max_s", "y1_gap_median_s", "step_ms_mean",
        "festival_contracts", "bot_fest_contracts_taken_player", "bot_fest_contracts_done_player", "contracts_failed",
        "contracts_done", "counter_sold", "upgrades_done", "hired", "caravans", "trips", "treaties", "visitors_per_day",
        "staff_hungry_share_max", "child_hungry_share_max", "npc_short_fun_max", "reputation", "townsfolk_end",
        "ai_broke_days_max", "game_over"]


def _arg(name, default=None):
    for a in sys.argv:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    if "--" + name in sys.argv:
        i = sys.argv.index("--" + name)
        if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith("--"):
            return sys.argv[i + 1]
        return True
    return default


def summarize_full(root, tag):
    folder = os.path.join(root, "reports", "full_player_" + tag)
    seeds = {}
    for f in sorted(os.listdir(folder)):
        if not f.endswith(".json") or not f[:-5].isdigit():
            continue
        d = json.load(open(os.path.join(folder, f)))
        m = d.get("measures", {})
        row = {k: m.get(k) for k in KEYS}
        row["needs_mean"] = d.get("town", {}).get("needs_mean", {})
        row["under_works_h"] = sum(int(s.get("hours", 0)) for s in d.get("stalls", []) if s.get("cause") == "under_works"
                                   and s.get("kind") == "character")
        row["titles"] = d.get("titles", [])
        row["why_not"] = {k: v.get("why") for k, v in d.get("mechanics", {}).items() if not v.get("used")}
        seeds[f[:-5]] = row
    agg = {}
    for k in KEYS + ["under_works_h"]:
        vals = [r[k] for r in seeds.values() if isinstance(r.get(k), (int, float))]
        if vals:
            agg[k] = {"median": round(statistics.median(vals), 2), "min": min(vals), "max": max(vals),
                      "mean": round(sum(vals) / len(vals), 2)}
    for need in ["fun", "hunger", "social", "rest", "faith"]:
        vals = [r["needs_mean"].get(need) for r in seeds.values() if r["needs_mean"].get(need) is not None]
        if vals:
            agg["need_" + need] = round(sum(vals) / len(vals), 1)
    return {"tag": tag, "kind": "full_player", "seeds": seeds, "agg": agg}


def summarize_pacing(root, tag):
    folder = os.path.join(root, "reports", "sim")
    out = {"tag": tag, "kind": "pacing"}
    for f in os.listdir(folder):
        if f.startswith("trial_" + tag + "_") and f.endswith(".json"):
            d = json.load(open(os.path.join(folder, f)))
            out["file"] = f
            out["misses"] = d.get("misses", [])
            keep = ("gap_", "goals_", "unlocks_", "gold_", "net_", "debt_paid", "upgrades_bought", "contracts_",
                    "fest_", "decisions", "hired", "counter_sold", "reputation", "title_citizen")
            out["aggregate"] = {k: v for k, v in d.get("aggregate", {}).items()
                                if any(k.split("_", 1)[1].startswith(x) for x in keep)}
    return out


def write(root, data):
    folder = os.path.join(root, "reports", "equilibrio")
    os.makedirs(folder, exist_ok=True)
    p = os.path.join(folder, data["tag"] + ".json")
    json.dump(data, open(p, "w"), indent=1, ensure_ascii=False, sort_keys=True)
    print("->", p)


def main():
    cmd = sys.argv[1]
    root = os.path.abspath(os.path.expanduser(_arg("root", ".")))
    tag = _arg("tag", "x")
    if cmd == "full":
        seeds = str(_arg("seeds", "1,2,3,4")).split(",")
        jobs = int(_arg("jobs", "2"))
        years = str(_arg("years", "3"))
        extra = [a for a in sys.argv if a.startswith("--bot=") or a.startswith("--set=")]
        groups = [seeds[i::jobs] for i in range(jobs) if seeds[i::jobs]]
        procs = []
        for g in groups:
            args = [GODOT, "--headless", "--path", root, "-s", "tools/full_player.gd", "--", "--years=" + years,
                    "--seed-list=" + ",".join(g), "--tag=" + tag, "--no-check"] + extra
            log = open("/tmp/eqm_%s_%s.log" % (tag, g[0]), "w")
            procs.append(subprocess.Popen(args, cwd=root, stdout=log, stderr=subprocess.STDOUT))
        for p in procs:
            p.wait()
        write(root, summarize_full(root, tag))
    elif cmd == "sum":
        write(root, summarize_full(root, tag))
    elif cmd == "pacing":
        args = [GODOT, "--headless", "--path", root, "-s", "tools/sim_runner.gd", "--", "--start=artisan_blacksmith",
                "--bots=pacing", "--days=8", "--seeds=" + str(_arg("seeds", "5")), "--tag=" + tag]
        if _arg("fl"):
            args += ["--festivals=on", "--life=on"]
        args += [a for a in sys.argv if a.startswith("--set=")]
        subprocess.run(args, cwd=root, stdout=open("/tmp/eqm_%s.log" % tag, "w"), stderr=subprocess.STDOUT)
        write(root, summarize_pacing(root, tag))
    elif cmd == "diff":
        a, b = json.load(open(sys.argv[2])), json.load(open(sys.argv[3]))
        for k in sorted(set(a.get("agg", {})) | set(b.get("agg", {}))):
            va, vb = a["agg"].get(k), b["agg"].get(k)
            fa = va["median"] if isinstance(va, dict) else va
            fb = vb["median"] if isinstance(vb, dict) else vb
            print("%-34s %12s -> %-12s" % (k, fa, fb))


if __name__ == "__main__":
    main()
