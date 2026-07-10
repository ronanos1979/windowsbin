#!/usr/bin/env python3
"""
Extract images/videos from an encrypted iPhone backup.

On Windows, iTunes backups live at:
  %APPDATA%\\Apple Computer\\MobileSync\\Backup\\<UUID>

Parameters:
  --list        Optional. List available backups and exit.
  --backup      Required unless --list is used. Backup UUID or full backup path.
  --output      Required unless --list is used. Destination folder for extracted files.
  --passphrase  Required unless --list is used. Backup encryption passphrase.
  --dry-run     Optional. Survey the manifest without extracting files.

Usage:
  python extract_iphone_backup.py --list
  python extract_iphone_backup.py --backup <path-or-UUID> --output <folder> --passphrase <pass>
  python extract_iphone_backup.py --backup <path-or-UUID> --output <folder> --passphrase <pass> --dry-run

Examples:
  python extract_iphone_backup.py --list
  python extract_iphone_backup.py ^
      --backup "00008030-0001391E0C40802E" ^
      --output "D:\\Backups\\iPhone_Images_20200816" ^
      --passphrase "MyPassword"

Requires:
  pip install iphone-backup-decrypt
"""

import argparse
import os
import shutil
import sys
from pathlib import Path
from collections import Counter


IMAGE_EXTENSIONS = {
    ".jpg", ".jpeg", ".jpg_temp",
    ".png", ".gif",
    ".heic", ".heif",
    ".bmp", ".tiff", ".tif",
    ".webp", ".raw", ".dng",
    ".svg", ".thm",
    ".mov", ".mp4", ".m4v", ".3gp",
}


def get_default_backup_root() -> Path:
    appdata = os.environ.get("APPDATA", "")
    candidates = [
        Path(appdata) / "Apple Computer" / "MobileSync" / "Backup",
        Path(appdata) / "Apple" / "MobileSync" / "Backup",
    ]
    for c in candidates:
        if c.exists():
            return c
    return candidates[0]


def resolve_backup_path(backup_arg: str) -> Path:
    p = Path(backup_arg)
    if p.is_dir():
        return p
    root = get_default_backup_root()
    candidate = root / backup_arg
    if candidate.is_dir():
        return candidate
    print(f"ERROR: Could not find backup at '{backup_arg}'", file=sys.stderr)
    print(f"       Searched: {backup_arg} and {candidate}", file=sys.stderr)
    sys.exit(1)


def list_backups():
    root = get_default_backup_root()
    if not root.exists():
        print(f"No backup folder found at: {root}")
        return
    print(f"iTunes backup folder: {root}\n")
    backups = [d for d in root.iterdir() if d.is_dir()]
    if not backups:
        print("No backups found.")
        return
    for b in sorted(backups):
        info_plist = b / "Info.plist"
        size_gb = sum(f.stat().st_size for f in b.rglob("*") if f.is_file()) / 1024**3
        print(f"  {b.name}  ({size_gb:.1f} GB)")
        if info_plist.exists():
            try:
                import plistlib
                with open(info_plist, "rb") as f:
                    info = plistlib.load(f)
                device = info.get("Device Name", "")
                ios    = info.get("Product Version", "")
                date   = info.get("Last Backup Date", "")
                print(f"    Device: {device}  iOS: {ios}  Date: {date}")
            except Exception:
                pass


def is_image(relative_path: str) -> bool:
    return Path(relative_path).suffix.lower() in IMAGE_EXTENSIONS


def check_disk_space(path: str, needed_gb: float = 10.0):
    try:
        _, _, free = shutil.disk_usage(path)
        free_gb = free / 1024**3
        print(f"Free space on {path}: {free_gb:.1f} GB")
        if free_gb < needed_gb:
            print(f"WARNING: Less than {needed_gb} GB free.", file=sys.stderr)
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser(
        description="Extract images/videos from an encrypted iPhone backup."
    )
    parser.add_argument("--list",       action="store_true", help="List available backups and exit.")
    parser.add_argument("--backup",     help="Backup UUID or full path to backup folder.")
    parser.add_argument("--output",     help="Output folder for extracted files.")
    parser.add_argument("--passphrase", help="Backup encryption passphrase.")
    parser.add_argument("--dry-run",    action="store_true", help="Survey manifest only, do not extract.")
    args = parser.parse_args()

    if args.list:
        list_backups()
        return

    if not args.backup or not args.output or not args.passphrase:
        parser.print_help()
        sys.exit(1)

    try:
        from iphone_backup_decrypt import EncryptedBackup
    except ImportError:
        print("ERROR: iphone-backup-decrypt is not installed.", file=sys.stderr)
        print("       Run: pip install iphone-backup-decrypt", file=sys.stderr)
        sys.exit(1)

    backup_path  = resolve_backup_path(args.backup)
    output_folder = args.output

    check_disk_space(str(Path(output_folder).anchor), needed_gb=10.0)
    os.makedirs(output_folder, exist_ok=True)

    print(f"\nBackup : {backup_path}")
    print(f"Output : {output_folder}")
    print(f"Dry run: {args.dry_run}")
    print("Decrypting manifest (may take 10-30 seconds)...")

    backup = EncryptedBackup(backup_directory=str(backup_path), passphrase=args.passphrase)

    print("Querying manifest...")
    with backup.manifest_db_cursor() as cur:
        cur.execute("SELECT domain, relativePath, flags FROM Files ORDER BY domain, relativePath")
        all_rows = cur.fetchall()

    regular_files = [(d, rp) for d, rp, f in all_rows if f == 1]
    image_files   = [(d, rp) for d, rp in regular_files if is_image(rp)]
    total_images  = len(image_files)

    print(f"\nTotal backup entries  : {len(all_rows)}")
    print(f"  Regular files       : {len(regular_files)}")
    print(f"  Image/video files   : {total_images}")

    domain_counts = Counter(d for d, _ in image_files)
    print("\nImages by domain:")
    for domain, count in sorted(domain_counts.items(), key=lambda x: -x[1]):
        print(f"  {count:5d}  {domain}")

    if total_images == 0:
        print("\nNo images found — check passphrase or backup path.", file=sys.stderr)
        sys.exit(1)

    if args.dry_run:
        print(f"\n[DRY RUN] Would extract {total_images} files to: {output_folder}")
        return

    print(f"\nExtracting {total_images} files...")
    extracted = [0]

    def image_filter(*, relative_path, domain, n, total_files, **kwargs):
        keep = is_image(relative_path)
        if keep:
            extracted[0] += 1
            if extracted[0] % 100 == 0:
                pct = extracted[0] / total_images * 100
                print(f"  [{pct:5.1f}%] {extracted[0]}/{total_images}", flush=True)
        return keep

    count = backup.extract_files(
        domain_like="%",
        output_folder=output_folder,
        preserve_folders=True,
        domain_subfolders=True,
        filter_callback=image_filter,
    )

    actual_on_disk = sum(1 for _ in Path(output_folder).rglob("*") if _.is_file())
    print("\n=== Done ===")
    print(f"API reported extracted : {count}")
    print(f"Files on disk          : {actual_on_disk}")
    print(f"Expected (manifest)    : {total_images}")
    if actual_on_disk < total_images:
        print(
            f"WARNING: {total_images - actual_on_disk} files may have been skipped or had name collisions.",
            file=sys.stderr,
        )
    print(f"\nOutput: {output_folder}")


if __name__ == "__main__":
    main()
