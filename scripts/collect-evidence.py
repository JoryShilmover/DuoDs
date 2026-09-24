#!/usr/bin/env python3
"""Collect a POC evidence run: pull the app's session-events.jsonl from a physical device or a
simulator, write artifacts/poc/<run-id>/{manifest.json, logs/, metrics/summary.json, report.md}.

Usage:
  scripts/collect-evidence.py --device <UDID>     [--run-id ID] [--operator NAME] [--since-boot N]
  scripts/collect-evidence.py --simulator <UDID>  [...]
  scripts/collect-evidence.py --events <file.jsonl> [...]   (re-analyse an existing log)

Metrics follow docs/poc/VALIDATION.md. They describe what the log shows; they do not by themselves
pass a gate (conditions, build type and hardware still matter). Output stays in ignored artifacts/.
"""
import argparse, datetime, hashlib, json, math, os, re, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "org.duods.prototype"
EVENTS = "Library/Application Support/DuoDS/session-events.jsonl"
DEV = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode-Beta.app/Contents/Developer")


def run(args, **kw):
    env = dict(os.environ, DEVELOPER_DIR=DEV)
    return subprocess.run(args, capture_output=True, text=True, env=env, **kw)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def pull(args, dest):
    if args.events:
        shutil.copy(args.events, dest)
    elif args.device:
        r = run(["xcrun", "devicectl", "device", "copy", "from", "--device", args.device,
                 "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
                 "--source", EVENTS, "--destination", str(dest)])
        if r.returncode:
            sys.exit("devicectl copy failed:\n" + r.stderr)
    else:
        r = run(["xcrun", "simctl", "get_app_container", args.simulator, BUNDLE, "data"])
        if r.returncode:
            sys.exit("simctl get_app_container failed:\n" + r.stderr)
        shutil.copy(Path(r.stdout.strip()) / EVENTS, dest)


def device_info(args):
    if args.device:
        text = run(["xcrun", "devicectl", "device", "info", "details", "--device", args.device]).stdout
        pick = lambda key: (re.search(rf"{key}:\s*(.+)", text) or [None, None])[1]
        return {"kind": "physical", "model": pick("marketingName") or pick("productType"),
                "os": pick("osVersionNumber") or pick("OS Version"), "identifier_class": "UDID (not recorded)"}
    if args.simulator:
        text = run(["xcrun", "simctl", "list", "devices", "-j"]).stdout
        for runtime, devices in json.loads(text)["devices"].items():
            for d in devices:
                if d["udid"] == args.simulator:
                    return {"kind": "simulator", "model": d["name"], "os": runtime.split(".")[-1]}
    return {"kind": "unknown"}


def manifest(args, run_id, device):
    lock = json.loads((ROOT / "Dependencies/lock.json").read_text())
    core = lock["dependencies"][0]
    head = run(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).stdout.strip()
    dirty = bool(run(["git", "-C", str(ROOT), "status", "--porcelain"]).stdout.strip())
    product = "Release-iphoneos" if args.device else "Debug-iphonesimulator"
    binary = ROOT / f"build/DerivedData/Build/Products/{product}/DuoDS.app/DuoDS"
    xcode = run(["xcodebuild", "-version"]).stdout.split()
    return {
        "run_id": run_id, "operator": args.operator,
        "collected_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "source_commit": head, "source_dirty": dirty,
        "core": {"name": core["name"], "commit": core["commit"],
                 "patch_sha256": sha256(ROOT / "Dependencies/patches/static-core.patch")},
        "binary": None if args.events else {"path": str(binary.relative_to(ROOT)),
                   "sha256": sha256(binary) if binary.exists() else None,
                   "note": "local build product; must match what is installed"},
        "bundle_id": BUNDLE, "xcode": " ".join(xcode[:4]) if xcode else None,
        "signing": "development (get-task-allow)" if args.device else "simulator (unsigned)" if args.simulator
                   else "unknown (re-analysed log file)",
        "device": device,
        "fixtures": "game field = content SHA-256 prefix; titles live in private artifacts/poc/private-corpus.md",
    }


def percentile(values, p):
    if not values:
        return None
    ordered = sorted(values)
    k = (len(ordered) - 1) * p
    lo, hi = math.floor(k), math.ceil(k)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (k - lo)


def analyse(events):
    """One summary per boot (session) in the log."""
    sessions, current = [], None
    for e in events:
        if e["event"] == "boot":
            current = {"game": e.get("game"), "events": []}
            sessions.append(current)
        if current is not None:
            current["events"].append(e)
    out = []
    for s in sessions:
        ev = s["events"]
        running = [e for e in ev if e["event"] == "checkpoint" and e["phase"] == "running" and e["core_fps"] > 0]
        speed_windows = []
        for a, b in zip(running, running[1:]):
            dt, df = b["monotonic"] - a["monotonic"], b["frames"] - a["frames"]
            if dt > 0 and df >= 0:
                speed_windows.append({"t": round(a["monotonic"] - ev[0]["monotonic"], 1), "fps": df / dt,
                                      "ratio": df / dt / b["core_fps"]})
        # 5-minute aggregates after a 5-minute warm-up (V07); shorter runs report what they have.
        start = ev[0]["monotonic"]
        five = {}
        for w in speed_windows:
            five.setdefault(int(w["t"] // 300), []).append(w["ratio"])
        last = ev[-1]
        first_run = running[0] if running else ev[0]
        touches = [e for e in ev if e["event"] == "touch-down"]
        accuracy = []
        for e in touches:
            m = re.search(r"view=([\d.]+),([\d.]+) rect=([\d.]+),([\d.]+),([\d.]+),([\d.]+) ds=(\d+),(\d+)", e.get("detail", ""))
            if not m:
                continue
            vx, vy, rx, ry, rw, rh, dx, dy = map(float, m.groups())
            # Independent reference mapping: same contract as CONTRACTS.md (256x192 over the drawn rect).
            ex = min(255, max(0, math.floor((vx - rx) * 256 / rw)))
            ey = min(191, max(0, math.floor((vy - ry) * 192 / rh)))
            accuracy.append(max(abs(ex - dx), abs(ey - dy)))
        latencies = [float(re.search(r"latency_ms=([\d.]+)", e["detail"]).group(1))
                     for e in ev if e["event"] == "touch-consumed" and "latency_ms" in e.get("detail", "")]
        duration = last["monotonic"] - start
        out.append({
            "game": s["game"], "duration_s": round(duration, 1), "frames": last["frames"],
            "core_target_fps": first_run.get("core_fps"),
            "speed": {"windows": len(speed_windows),
                      "min_ratio": round(min((w["ratio"] for w in speed_windows), default=0), 4),
                      "mean_ratio": round(sum(w["ratio"] for w in speed_windows) / len(speed_windows), 4) if speed_windows else None,
                      "five_minute_min_ratio": {str(k): round(min(v), 4) for k, v in sorted(five.items())},
                      "below_95pct_windows": sum(w["ratio"] < 0.95 for w in speed_windows)},
            "presentation": {"video_frames": last["video_frames"], "presented_unique": last.get("presented_unique"),
                             "unique_ratio": round(last["presented_unique"] / last["video_frames"], 4)
                             if last.get("presented_unique") and last["video_frames"] else None,
                             "repeated": last.get("presented_repeated"), "skipped": last.get("presented_skipped")},
            "audio": {"underruns": last["audio_underruns"], "overruns": last["audio_overruns"],
                      "underruns_per_10min": round(last["audio_underruns"] / duration * 600, 2) if duration > 0 else None,
                      "buffered_ms_range": [min((e.get("audio_buffered_ms", 0) for e in running), default=None),
                                            max((e.get("audio_buffered_ms", 0) for e in running), default=None)]},
            "touch": {"samples": len(touches), "max_mapping_error_px": max(accuracy) if accuracy else None,
                      "consumed": len(latencies), "latency_ms_p50": percentile(latencies, 0.5),
                      "latency_ms_p95": percentile(latencies, 0.95)},
            "thermal": {"max_state": max((e.get("thermal_state", 0) for e in ev), default=None),
                        "states": "0 nominal, 1 fair, 2 serious, 3 critical"},
            "energy": {"battery_start": first_run.get("battery_level"), "battery_end": last.get("battery_level"),
                       "battery_state_end": last.get("battery_state"), "low_power_mode": last.get("low_power_mode"),
                       "brightness": last.get("brightness")},
            "lifecycle": [e["event"] for e in ev if e["event"] not in ("checkpoint", "geometry", "touch-down", "touch-consumed")],
        })
    return out


def report(man, summaries):
    lines = [f"# POC run {man['run_id']}", "",
             f"Collected {man['collected_utc']} by {man['operator']} · source `{man['source_commit'][:10]}`"
             f"{' (dirty)' if man['source_dirty'] else ''} · core `{man['core']['commit'][:10]}` · {man['signing']}",
             f"Device: {man['device'].get('kind')} {man['device'].get('model')} {man['device'].get('os')}", "",
             "Metrics describe this log only. A gate passes only under VALIDATION.md conditions (release-like build, target hardware, stated duration).", ""]
    for i, s in enumerate(summaries, 1):
        sp, pr, au, to = s["speed"], s["presentation"], s["audio"], s["touch"]
        lines += [f"## Session {i} — game `{s['game']}`, {s['duration_s']} s, {s['frames']} frames", "",
                  "| Metric | Value | Target (VALIDATION.md) |", "|---|---|---|",
                  f"| Emulation speed, mean / min 10 s window | {sp['mean_ratio']} / {sp['min_ratio']} of {s['core_target_fps']:.4f} fps | ≥0.98 per 5-min window after warm-up (V07) |" if s['core_target_fps'] else "| Emulation speed | n/a | |",
                  f"| 5-minute window minimums | {sp['five_minute_min_ratio']} | ≥0.98 (V07) |",
                  f"| Windows below 95% | {sp['below_95pct_windows']} | no >3 s interval below 95% (V07) |",
                  f"| Unique presented / core frames | {pr['unique_ratio']} ({pr['presented_unique']}/{pr['video_frames']}), repeated {pr['repeated']}, skipped {pr['skipped']} | ≥0.95 (V09) |",
                  f"| Audio underruns | {au['underruns']} ({au['underruns_per_10min']}/10 min), cushion {au['buffered_ms_range']} ms | ≤1 per 10 min (V11) |",
                  f"| Touch mapping error (max) | {to['max_mapping_error_px']} px over {to['samples']} taps | ≤1 DS px (V10) |",
                  f"| Touch → core latency p50 / p95 | {to['latency_ms_p50']} / {to['latency_ms_p95']} ms ({to['consumed']} samples) | p95 ≤100 ms over 100 taps (V10) |",
                  f"| Thermal max state | {s['thermal']['max_state']} | no serious/critical (V12) |",
                  f"| Battery start → end | {s['energy']['battery_start']} → {s['energy']['battery_end']} (low power {s['energy']['low_power_mode']}, brightness {s['energy']['brightness']}) | record only (V12) |",
                  "", "Lifecycle: " + ", ".join(s["lifecycle"]), ""]
    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser()
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--device"); src.add_argument("--simulator"); src.add_argument("--events")
    p.add_argument("--run-id"); p.add_argument("--operator", default="agent")
    p.add_argument("--since-boot", type=int, default=0, help="only analyse the last N sessions (0 = all)")
    args = p.parse_args()
    kind = "device" if args.device else "sim" if args.simulator else "file"
    run_id = args.run_id or datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + "-" + kind
    out = ROOT / "artifacts/poc" / run_id
    (out / "logs").mkdir(parents=True, exist_ok=True); (out / "metrics").mkdir(exist_ok=True)
    events_path = out / "logs/session-events.jsonl"
    pull(args, events_path)
    events = [json.loads(line) for line in events_path.read_text().splitlines() if line.strip()]
    man = manifest(args, run_id, device_info(args))
    summaries = analyse(events)
    if args.since_boot:
        summaries = summaries[-args.since_boot:]
    (out / "manifest.json").write_text(json.dumps(man, indent=2) + "\n")
    (out / "metrics/summary.json").write_text(json.dumps(summaries, indent=2) + "\n")
    (out / "report.md").write_text(report(man, summaries) + "\n")
    print(f"Wrote {out.relative_to(ROOT)} ({len(events)} events, {len(summaries)} sessions)")


if __name__ == "__main__":
    main()
