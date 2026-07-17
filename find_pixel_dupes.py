#!/usr/bin/env python3
"""
find_pixel_dupes.py — Find and move pixel-identical image duplicates.

Scans every directory under SOURCE_ROOT and finds image files within the
SAME directory whose decoded pixel content is identical, even if their
filenames, sizes, or EXIF metadata differ.  Duplicates are MOVED (never
deleted) to DEST_ROOT, preserving the original directory structure, so
you can review them before deciding to delete.

Runs in DRY-RUN mode by default.  Pass --execute to actually move files.

Usage
-----
    python find_pixel_dupes.py <SOURCE_ROOT> <DEST_ROOT> [options]

Examples
--------
    # Preview what would be moved (safe, nothing changes)
    python find_pixel_dupes.py "F:\\Pictures" "F:\\Duplicates"

    # Actually move the duplicates
    python find_pixel_dupes.py "F:\\Pictures" "F:\\Duplicates" --execute

    # Keep the largest file instead of the oldest
    python find_pixel_dupes.py "F:\\Pictures" "F:\\Duplicates" --keep largest

    # Limit to JPEG files only
    python find_pixel_dupes.py "F:\\Pictures" "F:\\Duplicates" --ext .jpg .jpeg

    # Write a detailed log to a specific file
    python find_pixel_dupes.py "F:\\Pictures" "F:\\Duplicates" --log moves.log

Options
-------
    --execute           Move files (default: dry-run, no changes made)
    --keep {oldest|newest|largest|smallest|alpha}
                        Which copy to keep in each duplicate group.
                        oldest   = keep file with earliest modification time [default]
                        newest   = keep file with latest modification time
                        largest  = keep largest file on disk (most data preserved)
                        smallest = keep smallest file
                        alpha    = keep first filename alphabetically
    --ext EXT [EXT ...] File extensions to scan (default: jpg jpeg png heic
                        heif tiff tif bmp webp)
    --log FILE          Path to log file (default: find_pixel_dupes.log in
                        current directory)
    --no-log            Suppress log file output (print to console only)
    -v, --verbose       Show per-file progress while hashing
    -h, --help          Show this help message and exit

How it works
------------
Each image is opened with Pillow, converted to raw RGB pixels, and hashed
with MD5.  Two files with the same pixel hash contain the same image data.
EXIF, thumbnails, color profiles, and other metadata are ignored, so files
that are byte-different but visually identical will be detected as duplicates.

Safety notes
------------
  * Dry-run is the default — nothing moves unless you pass --execute.
  * Files are MOVED, not deleted.  The destination tree mirrors the source.
  * A full log of every decision is written so you can audit or undo.
  * If DEST_ROOT is inside SOURCE_ROOT the script will abort (prevents loops).
  * Files that cannot be decoded (corrupt, unsupported format) are skipped
    with a warning and never touched.
  * Within each duplicate group the chosen keeper is logged clearly.
"""

import argparse
import hashlib
import logging
import os
import shutil
import sys
from collections import defaultdict
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("ERROR: Pillow is not installed.  Run:  pip install Pillow")

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
    _HEIC_SUPPORT = True
except ImportError:
    _HEIC_SUPPORT = False

DEFAULT_EXTENSIONS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".tiff", ".tif", ".bmp", ".webp"}
LOG_FORMAT = "%(message)s"


# ---------------------------------------------------------------------------
# Core helpers
# ---------------------------------------------------------------------------

def pixel_hash(path: Path, verbose: bool = False) -> str | None:
    """Return MD5 of decoded RGB pixel data, or None on error."""
    if verbose:
        logging.info(f"  hashing {path.name} …")
    try:
        with Image.open(path) as img:
            return hashlib.md5(img.convert("RGB").tobytes()).hexdigest(), img.size
    except Exception as exc:
        logging.warning(f"  SKIP (cannot decode): {path}  [{exc}]")
        return None, None


def pick_keeper(files: list[Path], strategy: str) -> Path:
    """Choose which file to keep from a duplicate group."""
    if strategy == "oldest":
        return min(files, key=lambda f: f.stat().st_mtime)
    if strategy == "newest":
        return max(files, key=lambda f: f.stat().st_mtime)
    if strategy == "largest":
        return max(files, key=lambda f: f.stat().st_size)
    if strategy == "smallest":
        return min(files, key=lambda f: f.stat().st_size)
    if strategy == "alpha":
        return min(files, key=lambda f: f.name.lower())
    raise ValueError(f"Unknown keep strategy: {strategy!r}")


def fmt_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


# ---------------------------------------------------------------------------
# Directory scanner
# ---------------------------------------------------------------------------

def scan_directory(directory: Path, extensions: set[str], verbose: bool) -> list[list[Path]]:
    """Return groups of pixel-identical files found in `directory` (non-recursive)."""
    buckets: dict[str, list[Path]] = defaultdict(list)

    image_files = [
        f for f in directory.iterdir()
        if f.is_file() and f.suffix.lower() in extensions
    ]

    if not image_files:
        return []

    for f in sorted(image_files):
        h, size = pixel_hash(f, verbose)
        if h:
            buckets[(h, size)].append(f)

    return [group for group in buckets.values() if len(group) > 1]


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="find_pixel_dupes.py",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("source_root", metavar="SOURCE_ROOT",
                   help="Root directory to scan recursively")
    p.add_argument("dest_root", metavar="DEST_ROOT",
                   help="Directory to move duplicates into (created if needed)")
    p.add_argument("--execute", action="store_true",
                   help="Actually move files (default: dry-run)")
    p.add_argument("--keep",
                   choices=["oldest", "newest", "largest", "smallest", "alpha"],
                   default="oldest",
                   help="Which copy to keep per duplicate group (default: oldest)")
    p.add_argument("--ext", nargs="+", metavar="EXT",
                   help="Extensions to scan, e.g. --ext .jpg .jpeg  (default: common image types)")
    p.add_argument("--log", metavar="FILE", default="find_pixel_dupes.log",
                   help="Log file path (default: find_pixel_dupes.log)")
    p.add_argument("--no-log", action="store_true",
                   help="Do not write a log file")
    p.add_argument("-v", "--verbose", action="store_true",
                   help="Show per-file hashing progress")
    return p


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    # --- logging setup ---
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    if not args.no_log:
        handlers.append(logging.FileHandler(args.log, encoding="utf-8"))
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, handlers=handlers)
    log = logging.getLogger()

    source = Path(args.source_root).resolve()
    dest = Path(args.dest_root).resolve()
    dry_run = not args.execute

    extensions = {e if e.startswith(".") else f".{e}" for e in (args.ext or [])}
    extensions = extensions or DEFAULT_EXTENSIONS
    extensions = {e.lower() for e in extensions}

    if not _HEIC_SUPPORT and any(e in extensions for e in (".heic", ".heif")):
        log.warning("WARNING: pillow-heif not installed — HEIC/HEIF files will be skipped.")
        log.warning("         Install with:  pip install pillow-heif\n")

    # Safety: refuse to move files into a subdirectory of source
    try:
        dest.relative_to(source)
        sys.exit(f"ERROR: DEST_ROOT ({dest}) is inside SOURCE_ROOT ({source}). "
                 "This would create a loop. Choose a different destination.")
    except ValueError:
        pass  # dest is not inside source — good

    if dry_run:
        log.info("=" * 70)
        log.info("DRY-RUN MODE  — no files will be moved.")
        log.info("Add --execute to actually move files.")
        log.info("=" * 70)
    else:
        log.info("=" * 70)
        log.info("EXECUTE MODE  — files WILL be moved.")
        log.info("=" * 70)

    log.info(f"Source : {source}")
    log.info(f"Dest   : {dest}")
    log.info(f"Keep   : {args.keep} copy per group")
    log.info(f"Ext    : {', '.join(sorted(extensions))}")
    if not args.no_log:
        log.info(f"Log    : {args.log}")
    log.info("")

    total_groups = 0
    total_files_moved = 0
    total_bytes_saved = 0
    errors = 0

    # Walk every directory (including source root itself)
    for root, dirs, _ in os.walk(source):
        dirs.sort()  # deterministic order
        directory = Path(root)
        rel_dir = directory.relative_to(source) if directory != source else Path(".")

        groups = scan_directory(directory, extensions, args.verbose)
        if not groups:
            continue

        for group in groups:
            total_groups += 1
            keeper = pick_keeper(group, args.keep)
            to_move = [f for f in group if f != keeper]

            log.info(f"[GROUP {total_groups}] {rel_dir}")
            log.info(f"  KEEP : {keeper.name}  ({fmt_size(keeper.stat().st_size)},"
                     f"  modified {_fmt_mtime(keeper)})")

            for f in to_move:
                rel_path = f.relative_to(source)
                target = dest / rel_path
                size = f.stat().st_size

                log.info(f"  MOVE : {f.name}  ({fmt_size(size)})  ->  {target}")

                if not dry_run:
                    try:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.move(str(f), str(target))
                        total_files_moved += 1
                        total_bytes_saved += size
                    except Exception as exc:
                        log.error(f"  ERROR moving {f}: {exc}")
                        errors += 1
                else:
                    total_files_moved += 1
                    total_bytes_saved += size

            log.info("")

    # Summary
    log.info("=" * 70)
    log.info("SUMMARY")
    log.info(f"  Duplicate groups found : {total_groups}")
    action = "moved" if not dry_run else "would be moved"
    log.info(f"  Files {action}          : {total_files_moved}")
    log.info(f"  Space {action}          : {fmt_size(total_bytes_saved)}")
    if errors:
        log.info(f"  Errors                 : {errors}  (see log for details)")
    if dry_run:
        log.info("")
        log.info("Run with --execute to move the files listed above.")
    log.info("=" * 70)


def _fmt_mtime(path: Path) -> str:
    import datetime
    ts = path.stat().st_mtime
    return datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")


if __name__ == "__main__":
    main()
