#!/usr/bin/env python3
"""
Compare images/videos across multiple iPhone backup extractions and deduplicate.

Strategy: hash-based (SHA-256). For a given TARGET folder, delete any file whose
content already exists in one of the REFERENCE folders. Reference folders are never
modified.

Parameters:
  --target   Required. Folder to remove duplicate files from.
  --refs     Required. One or more reference folders; these are scanned but never modified.
  --dry-run  Optional. Report what would be deleted without touching files.

Usage:
  python deduplicate_backups.py --target <folder> --refs <folder> [<folder> ...]  [--dry-run]

Example — deduplicate ThirdBackup against both First and Second:
  python deduplicate_backups.py ^
      --target  "D:\\Backups\\ThirdBackup\\iPhone_Images_20220118" ^
      --refs    "D:\\Backups\\FirstBackup\\iPhone_Images_20200816" ^
                "D:\\Backups\\SecondBackup\\iPhone_Images_20200906"
"""

import argparse
import hashlib
import sys
from pathlib import Path
from collections import defaultdict


def sha256(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(chunk), b""):
            h.update(block)
    return h.hexdigest()


def collect_hashes(folder: Path) -> dict:
    hashes = defaultdict(list)
    files = [p for p in folder.rglob("*") if p.is_file()]
    total = len(files)
    print(f"  Hashing {total} files in {folder.name}...")
    for i, p in enumerate(files, 1):
        if i % 500 == 0:
            print(f"    {i}/{total}", flush=True)
        try:
            hashes[sha256(p)].append(p)
        except OSError as e:
            print(f"  SKIP (unreadable): {p} — {e}", file=sys.stderr)
    return hashes


def main():
    parser = argparse.ArgumentParser(description="Deduplicate iPhone backup extractions.")
    parser.add_argument("--target", required=True, help="Folder to remove duplicates from.")
    parser.add_argument("--refs",   required=True, nargs="+", help="Reference folders (never modified).")
    parser.add_argument("--dry-run", action="store_true", help="Report only, do not delete.")
    args = parser.parse_args()

    target = Path(args.target)
    refs   = [Path(r) for r in args.refs]

    for p in [target] + refs:
        if not p.exists():
            print(f"ERROR: {p} does not exist.", file=sys.stderr)
            sys.exit(1)

    print("=== Deduplication ===")
    print(f"Target (duplicates removed from): {target}")
    for r in refs:
        print(f"Reference (kept intact)         : {r}")
    print(f"Dry run: {args.dry_run}\n")

    ref_hashes: set = set()
    for i, ref in enumerate(refs, 1):
        print(f"Step {i}: Hashing reference — {ref.name}...")
        h = collect_hashes(ref)
        print(f"  Unique files: {len(h)}")
        ref_hashes.update(h.keys())

    print(f"\nCombined unique hashes across all references: {len(ref_hashes)}")

    print(f"\nStep {len(refs)+1}: Hashing target — {target.name}...")
    target_hashes = collect_hashes(target)
    print(f"  Unique files in target: {len(target_hashes)}")

    dup_hashes    = set(target_hashes) & ref_hashes
    unique_hashes = set(target_hashes) - ref_hashes

    dup_files    = [p for h in dup_hashes    for p in target_hashes[h]]
    unique_files = [p for h in unique_hashes for p in target_hashes[h]]

    print("\n=== Results ===")
    print(f"Duplicates in target (already in a reference): {len(dup_files)}")
    print(f"Unique to target (will be kept)              : {len(unique_files)}")

    if args.dry_run:
        print(f"\n[DRY RUN] Would delete {len(dup_files)} files.")
        print(f"[DRY RUN] Would keep   {len(unique_files)} files.")
        return

    deleted = 0
    errors  = 0
    for p in dup_files:
        try:
            p.unlink()
            deleted += 1
        except OSError as e:
            print(f"  ERROR deleting {p}: {e}", file=sys.stderr)
            errors += 1

    for d in sorted(target.rglob("*"), reverse=True):
        if d.is_dir() and not any(d.iterdir()):
            d.rmdir()

    print(f"\nDeleted {deleted} duplicates from target ({errors} errors).")
    print(f"Target now contains {len(unique_files)} files unique to this backup.")
    print("\nMaster collection:")
    for r in refs:
        print(f"  {r}")
    print(f"  {target}  ({len(unique_files)} unique files)")
    total_ref = sum(len(list(Path(r).rglob("*"))) for r in refs if r.exists())
    print(f"\nTotal unique images/videos: ~{total_ref + len(unique_files)}")


if __name__ == "__main__":
    main()
