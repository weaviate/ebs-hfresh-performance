#!/usr/bin/env python3
"""Turn results/ into results/summary.md and charts/*.png.

Inputs (produced by scripts/run-phase.sh):
  results/<phase>/probe-sweep-p<N>.json   benchmarker JSON arrays, one record per searchProbe
  results/<phase>/rescore-r<R>-p32.json   rescoreLimit sensitivity
  results/<phase>/sweep/iostat.json       sysstat JSON (iostat -x -o JSON -d 1)
  results/<phase>/sweep/cgroup-mem.csv    ts,memory_current_bytes,anon_bytes,file_bytes
  results/<phase>/fio-summary.txt         provisioned-limit calibration
Usage: python3 scripts/analyze/render.py [--results results] [--out blog/diagrams]
"""
import argparse, glob, json, os, re, sys
from datetime import datetime, timezone
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

PHASES = [  # display order, colours from the validated categorical palette (slots 1-4)
    ("phase-1-baseline", "gp3 baseline (3,000 IOPS / 125 MiB/s)", "#2a78d6"),
    ("phase-2-max",      "gp3 max (80,000 IOPS / 2,000 MiB/s)",  "#eb6834"),
    ("phase-3-control",  "control: 56 GiB RAM, gp3 max",          "#1baf7a"),
    ("phase-2-max-mmap", "gp3 max, mmap (first attempt)",         "#eda100"),
    ("phase-4-nvme",     "instance-store NVMe (i4i)",              "#4a3aa7"),
]
PROVISIONED_IOPS = {"phase-1-baseline": 3000, "phase-2-max": 80000, "phase-3-control": 80000, "phase-2-max-mmap": 80000, "phase-4-nvme": None}
IOS_PER_QUERY = 64 + 350  # searchProbe postings + rescoreLimit object reads at defaults
TEXT, MUTED, GRID = "#0b0b0b", "#52514e", "#e6e5e1"


def first(rec, *keys, default=None):
    for k in keys:
        if k in rec and rec[k] not in (None, ""):
            return rec[k]
    return default


def load_bench(results):
    rows = []
    for phase, _, _ in PHASES:
        for path in glob.glob(os.path.join(results, phase, "*.json")):
            name = os.path.basename(path)
            if name.startswith("schema") or name.startswith("warmup"):
                continue
            try:
                data = json.load(open(path))
            except Exception as e:
                print(f"skip {path}: {e}", file=sys.stderr); continue
            if isinstance(data, dict):
                data = [data]
            for rec in data:
                if not isinstance(rec, dict) or first(rec, "qps", "queriesPerSecond") is None:
                    continue
                rows.append({
                    "phase": phase,
                    "kind": rec.get("kind", "probe" if "probe" in name else "rescore"),
                    "parallel": int(first(rec, "parallelization", "parallel", default=0)),
                    "searchProbe": int(first(rec, "searchProbe", "ef", default=0)),
                    "rescoreLimit": int(first(rec, "rescore", "rescoreLimit", default=350) or 350),
                    "qps": float(first(rec, "qps", "queriesPerSecond")),
                    "recall": float(first(rec, "recall", default=float("nan"))),
                    "mean_ms": 1000 * float(first(rec, "meanLatency", "mean", default=float("nan"))),
                    "p99_ms": 1000 * float(first(rec, "p99Latency", "p99", default=float("nan"))),
                    "timestamp": first(rec, "timestamp"),
                    "file": name,
                })
    return pd.DataFrame(rows)


def load_iostat(path):
    if not os.path.exists(path):
        return pd.DataFrame()
    try:
        j = json.load(open(path))
    except Exception as e:
        print(f"iostat parse failed {path}: {e}", file=sys.stderr); return pd.DataFrame()
    rows = []
    for host in j.get("sysstat", {}).get("hosts", []):
        for st in host.get("statistics", []):
            for d in st.get("disk", []):
                rkb = first(d, "rkB/s", default=None)
                rmb = first(d, "rMB/s", default=None)
                rows.append({
                    "ts": st.get("timestamp"),
                    "r_s": float(first(d, "r/s", default=0)),
                    "rmb_s": float(rmb) if rmb is not None else float(rkb or 0) / 1024,
                    "rareq_kb": float(first(d, "rareq-sz", default=0)),
                    "r_await_ms": float(first(d, "r_await", default=0)),
                    "aqu_sz": float(first(d, "aqu-sz", default=0)),
                    "util": float(first(d, "util", default=0)),
                })
    df = pd.DataFrame(rows)
    if not df.empty:
        # sysstat writes e.g. "09/08/2026 01:18:12 PM" (locale dependent); sample interval is 1 s,
        # so fall back to the row index when the timestamps do not parse.
        t = pd.to_datetime(df["ts"], errors="coerce", format="mixed", dayfirst=False)
        if t.notna().sum() > len(df) * 0.9:
            df["sec"] = (t - t.dropna().iloc[0]).dt.total_seconds()
        else:
            df["sec"] = range(len(df))
    return df


def load_cgroup(path):
    if not os.path.exists(path):
        return pd.DataFrame()
    df = pd.read_csv(path)
    for c in ("memory_current_bytes", "anon_bytes", "file_bytes"):
        df[c.replace("_bytes", "_gib")] = df[c] / 2**30
    df["sec"] = df["ts"] - df["ts"].iloc[0]
    return df


def load_fio(path):
    if not os.path.exists(path):
        return {}
    return dict(kv.split("=") for kv in open(path).read().split() if "=" in kv)


def style(ax, ylabel, xlabel=None, title=None):
    ax.set_facecolor("#fcfcfb")
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    for s in ("left", "bottom"):
        ax.spines[s].set_color(GRID)
    ax.grid(axis="y", color=GRID, linewidth=0.8); ax.set_axisbelow(True)
    ax.tick_params(colors=MUTED, labelsize=9)
    ax.set_ylabel(ylabel, color=MUTED, fontsize=9)
    if xlabel: ax.set_xlabel(xlabel, color=MUTED, fontsize=9)
    if title: ax.set_title(title, color=TEXT, fontsize=11, loc="left", pad=12)


def save(fig, out, name):
    fig.patch.set_facecolor("#fcfcfb"); fig.tight_layout()
    p = os.path.join(out, name); fig.savefig(p, dpi=160); plt.close(fig); print("wrote", p)


def chart_qps_vs_probe(df, out):
    d = df[(df.kind == "probe") & (df.parallel == 32)]
    if d.empty: return
    fig, ax = plt.subplots(figsize=(7, 4))
    for phase, label, color in PHASES:
        s = d[d.phase == phase].sort_values("searchProbe")
        if s.empty: continue
        ax.plot(s.searchProbe, s.qps, marker="o", ms=6, lw=2, color=color, label=label)
        ax.annotate(f"{s.qps.iloc[-1]:.0f}", (s.searchProbe.iloc[-1], s.qps.iloc[-1]), xytext=(6, 0),
                    textcoords="offset points", fontsize=9, color=TEXT, va="center")
    ax.set_xscale("log", base=2); ax.set_xticks([32, 64, 128, 256]); ax.set_xticklabels(["32", "64", "128", "256 (default)"])
    style(ax, "queries per second", "searchProbe (posting lists read per query)",
          "Same node, same data, 8 GiB RAM cap: QPS vs searchProbe at 32 clients")
    ax.legend(frameon=False, fontsize=9, labelcolor=TEXT)
    save(fig, out, "01-qps-vs-searchprobe.png")


def chart_qps_vs_parallel(df, out):
    d = df[(df.kind == "probe") & (df.searchProbe == 64)]
    if d.empty: return
    fig, ax = plt.subplots(figsize=(7, 4))
    for phase, label, color in PHASES:
        s = d[d.phase == phase].sort_values("parallel")
        if s.empty: continue
        ax.plot(s.parallel, s.qps, marker="o", ms=6, lw=2, color=color, label=label)
    for iops, color in ((3000, "#2a78d6"), (80000, "#eb6834")):
        ceil = iops / IOS_PER_QUERY
        ax.axhline(ceil, color=color, lw=1, ls="--", alpha=0.7)
        ax.annotate(f"predicted ceiling: {iops:,} IOPS / {IOS_PER_QUERY} IO per query = {ceil:.0f} QPS", (128, ceil), xytext=(0, -11),
                    textcoords="offset points", fontsize=8, color=MUTED, ha="right")
    ax.set_xscale("log", base=2); ax.set_xticks([8, 32, 128]); ax.set_xticklabels(["8", "32", "128"])
    style(ax, "queries per second", "concurrent clients", "QPS vs concurrency at searchProbe 64")
    ax.legend(frameon=False, fontsize=9, labelcolor=TEXT, loc="upper center", bbox_to_anchor=(0.5, -0.2), ncol=1)
    save(fig, out, "02-qps-vs-parallel.png")


def chart_iostat(results, out):
    have = [(ph, lb, c, load_iostat(os.path.join(results, ph, "sweep", "iostat.json"))) for ph, lb, c in PHASES]
    have = [h for h in have if not h[3].empty]
    if not have: return
    fig, axes = plt.subplots(len(have), 1, figsize=(8, 2.4 * len(have)), sharex=False)
    axes = list(axes) if len(have) > 1 else [axes]
    any_data = False
    for ax, (phase, label, color, io) in zip(axes, have):
        any_data = True
        ax.plot(io.sec / 60, io.r_s, lw=1, color=color)
        prov = PROVISIONED_IOPS.get(phase, 80000)
        if prov:
            ax.axhline(prov, color=MUTED, lw=1, ls="--")
            ax.annotate(f"provisioned {prov:,} IOPS", (0, prov), xytext=(2, 4), textcoords="offset points", fontsize=8, color=MUTED)
            ax.set_ylim(0, prov * 1.15)
        else:
            ax.set_ylim(0, max(io.r_s.max() * 1.15, 1))
        style(ax, "read IOPS", "minutes into sweep", label)
    if any_data: save(fig, out, "03-iostat-read-iops.png")
    else: plt.close(fig)


def chart_p99(df, out):
    d = df[df.kind == "probe"]
    if d.empty: return
    fig, ax = plt.subplots(figsize=(7, 4))
    for phase, label, color in PHASES:
        s = d[d.phase == phase].sort_values("qps")
        if s.empty: continue
        ax.scatter(s.qps, s.p99_ms, s=36, color=color, label=label, edgecolors="#fcfcfb", linewidths=1)
    ax.set_yscale("log")
    style(ax, "p99 latency (ms, log)", "queries per second", "Latency vs throughput, every sweep point")
    ax.legend(frameon=False, fontsize=9, labelcolor=TEXT)
    save(fig, out, "04-p99-vs-qps.png")


def chart_memory(results, out):
    fig, ax = plt.subplots(figsize=(7, 4.4))
    any_data = False
    for phase, label, color in [p for p in PHASES if p[0] in ("phase-1-baseline", "phase-2-max", "phase-2-max-mmap", "phase-4-nvme")]:
        cg = load_cgroup(os.path.join(results, phase, "sweep", "cgroup-mem.csv"))
        if cg.empty: continue
        any_data = True
        ax.plot(cg.sec / 60, cg.memory_current_gib, lw=2, color=color, label=f"{label}: total")
        ax.plot(cg.sec / 60, cg.anon_gib, lw=1, ls=":", color=color, label=f"{label}: anon (heap)")
    if not any_data: plt.close(fig); return
    ax.axhline(8, color=MUTED, lw=1, ls="--"); ax.annotate("8 GiB cgroup cap", (0, 8), xytext=(2, 4), textcoords="offset points", fontsize=8, color=MUTED)
    ax.set_ylim(0, 9)
    style(ax, "GiB", "minutes into sweep", "Container memory during the 8 GiB phases (page cache included)")
    ax.legend(frameon=False, fontsize=8, labelcolor=TEXT, ncol=2, loc="upper center", bbox_to_anchor=(0.5, -0.22))
    save(fig, out, "05-cgroup-memory.png")


def chart_rescore(df, out):
    d = df[df.kind == "rescore"]
    if d.empty: return
    fig, ax = plt.subplots(figsize=(7, 3.6))
    for phase, label, color in PHASES:
        s = d[d.phase == phase].sort_values("rescoreLimit")
        if s.empty: continue
        ax.plot(s.rescoreLimit, s.qps, marker="o", ms=6, lw=2, color=color, label=label)
    ax.set_xscale("log"); ax.set_xticks([100, 350, 1000]); ax.set_xticklabels(["100", "350", "1000"])
    style(ax, "queries per second", "rescoreLimit (full-precision reads per query)", "rescoreLimit sensitivity at searchProbe 64 / 32 clients")
    ax.legend(frameon=False, fontsize=9, labelcolor=TEXT)
    save(fig, out, "06-rescore-sensitivity.png")


def summary(df, results):
    lines = ["# Results summary", "", f"Generated {datetime.now(timezone.utc):%Y-%m-%d %H:%M UTC}", ""]
    lines += ["## Volume calibration (fio, before each phase)", "", "| phase | 4k randread IOPS | mean read latency (us) | 1M seqread MiB/s |", "|---|---|---|---|"]
    for phase, label, _ in PHASES:
        f = load_fio(os.path.join(results, phase, "fio-summary.txt"))
        if f: lines.append(f"| {label} | {f.get('randread_4k_iops')} | {f.get('randread_4k_mean_lat_us')} | {f.get('seqread_1m_mib_s')} |")
    if not df.empty:
        lines += ["", "## Query sweep (searchProbe x clients)", "", "| phase | clients | searchProbe | QPS | recall@10 | mean ms | p99 ms |", "|---|---|---|---|---|---|---|"]
        for phase, label, _ in PHASES:
            for _, r in df[(df.kind == "probe") & (df.phase == phase)].sort_values(["parallel", "searchProbe"]).iterrows():
                lines.append(f"| {label} | {r.parallel} | {r.searchProbe} | {r.qps:.1f} | {r.recall:.3f} | {r.mean_ms:.0f} | {r.p99_ms:.0f} |")
        lines += ["", "## rescoreLimit sensitivity (searchProbe 64, 32 clients)", "", "| phase | rescoreLimit | QPS | recall@10 | p99 ms |", "|---|---|---|---|---|"]
        for phase, label, _ in PHASES:
            for _, r in df[(df.kind == "rescore") & (df.phase == phase)].sort_values("rescoreLimit").iterrows():
                lines.append(f"| {label} | {r.rescoreLimit} | {r.qps:.1f} | {r.recall:.3f} | {r.p99_ms:.0f} |")
        head = df[(df.kind == "probe") & (df.parallel == 32) & (df.searchProbe == 64)].set_index("phase")
        if {"phase-1-baseline", "phase-2-max"} <= set(head.index):
            b, m = head.loc["phase-1-baseline", "qps"], head.loc["phase-2-max", "qps"]
            lines += ["", f"**Headline (32 clients, searchProbe 64):** {b:.1f} QPS at baseline vs {m:.1f} QPS at max = **{m / b:.1f}x** on the same node, data and 8 GiB cap."]
    lines += ["", "## Disk telemetry during sweeps (iostat, per phase)", "", "| phase | mean read IOPS | peak read IOPS | mean rMiB/s | mean read size KiB | mean r_await ms | mean util % |", "|---|---|---|---|---|---|---|"]
    for phase, label, _ in PHASES:
        io = load_iostat(os.path.join(results, phase, "sweep", "iostat.json"))
        if io.empty: continue
        busy = io[io.r_s > 50]
        if busy.empty: busy = io
        lines.append(f"| {label} | {busy.r_s.mean():.0f} | {busy.r_s.max():.0f} | {busy.rmb_s.mean():.1f} | {busy.rareq_kb.mean():.1f} | {busy.r_await_ms.mean():.2f} | {busy.util.mean():.0f} |")
    lines += ["", "## Container memory (cgroup memory.current)", "", "| phase | peak GiB | peak anon GiB | peak file (page cache) GiB |", "|---|---|---|---|"]
    for phase, label, _ in PHASES:
        cg = load_cgroup(os.path.join(results, phase, "sweep", "cgroup-mem.csv"))
        if cg.empty: continue
        lines.append(f"| {label} | {cg.memory_current_gib.max():.2f} | {cg.anon_gib.max():.2f} | {cg.file_gib.max():.2f} |")
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", default="results"); ap.add_argument("--out", default="charts")
    ap.add_argument("--phases", default="phase-1-baseline,phase-2-max,phase-3-control,phase-2-max-mmap",
                    help="comma-separated phase ids to include (the EBS post's set by default)")
    ap.add_argument("--summary", default=None, help="summary path (default <results>/summary.md)")
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    global PHASES
    keep = a.phases.split(","); PHASES = [p for p in PHASES if p[0] in keep]
    df = load_bench(a.results)
    print(f"{len(df)} benchmark records across {df.phase.nunique() if not df.empty else 0} phases")
    if not df.empty:
        chart_qps_vs_probe(df, a.out); chart_qps_vs_parallel(df, a.out); chart_p99(df, a.out); chart_rescore(df, a.out)
    chart_iostat(a.results, a.out); chart_memory(a.results, a.out)
    md = summary(df, a.results)
    sp = a.summary or os.path.join(a.results, "summary.md")
    open(sp, "w").write(md); print("wrote", sp)


if __name__ == "__main__":
    main()
