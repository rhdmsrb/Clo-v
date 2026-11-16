#!/usr/bin/env python3
"""Fill the curated clothing catalog (public.catalog_items + private
`catalog-items` bucket) with openly licensed Openverse photos, keeping the
creator, license and source link on every row.

Dry run by default. Writing needs --apply plus SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY in the environment (the key bypasses RLS: keep it out
of the repo and shell history). Re-running skips photos already in the catalog.

  python3 scripts/seed_catalog_from_openverse.py
  python3 scripts/seed_catalog_from_openverse.py --per-category 6 --apply
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

from seed_wardrobe_from_openverse import (  # same directory
    CATEGORIES, REQUEST_TIMEOUT_SECONDS, USER_AGENT, download, search, supabase_request, usable,
)

BUCKET = "catalog-items"
MAX_NAME_LENGTH = 80


def license_label(image):
    version = f" {image['license_version']}" if image.get("license_version") else ""
    return f"{image['license'].upper()}{version}"


SEARCH_ATTEMPTS = 3
SEARCH_RETRY_SECONDS = 3


def search_with_retry(query, count):
    for attempt in range(1, SEARCH_ATTEMPTS + 1):
        try:
            return search(query, count)
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt == SEARCH_ATTEMPTS:
                print(f"search failed for {query!r}: {error}", file=sys.stderr)
                return []
            time.sleep(SEARCH_RETRY_SECONDS * attempt)
    return []


def existing_sources(base_url, key):
    url = f"{base_url}/rest/v1/catalog_items?select=source_url&limit=1000"
    request = urllib.request.Request(url, headers={"apikey": key, "Authorization": f"Bearer {key}", "User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return {row["source_url"] for row in json.load(response) if row.get("source_url")}


def insert_item(base_url, key, category, image, data, sort_order):
    path = f"{category}/{uuid.uuid4()}.jpg"
    supabase_request("POST", f"{base_url}/storage/v1/object/{BUCKET}/{path}", key, data, "image/jpeg")
    title = (image.get("title") or "").split(" / ")[0].strip()[:MAX_NAME_LENGTH] or f"{category.title()} piece"
    https_or_none = lambda value: value if isinstance(value, str) and value.startswith("https://") else None
    row = {
        "name": title,
        "category": category,
        "image_path": path,
        "creator": (image.get("creator") or "").strip() or None,
        "license": license_label(image),
        "license_url": https_or_none(image.get("license_url")),
        "source_url": https_or_none(image.get("foreign_landing_url")),
        "tags": [t["name"] for t in (image.get("tags") or []) if t.get("name")][:8],
        "sort_order": sort_order,
    }
    try:
        supabase_request("POST", f"{base_url}/rest/v1/catalog_items", key, json.dumps(row).encode())
    except urllib.error.URLError:
        supabase_request("DELETE", f"{base_url}/storage/v1/object/{BUCKET}/{path}", key)  # no orphan file
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--per-category", type=int, default=6)
    parser.add_argument("--categories", nargs="+", choices=sorted(CATEGORIES), default=sorted(CATEGORIES))
    parser.add_argument("--apply", action="store_true", help="actually upload (default: dry run)")
    args = parser.parse_args()

    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if args.apply and not (base_url.startswith("https://") and key):
        sys.exit("--apply needs SUPABASE_URL (https) and SUPABASE_SERVICE_ROLE_KEY in the environment.")
    seen = existing_sources(base_url, key) if args.apply else set()

    total = 0
    for category in args.categories:
        taken = 0
        for image in search_with_retry(CATEGORIES[category], args.per_category):
            if taken >= args.per_category:
                break
            source = image.get("foreign_landing_url")
            if not usable(image) or (source and source in seen):
                continue
            label = f"[{category}] {image.get('title') or image['id']} - {license_label(image)} - {image.get('creator') or 'unknown'}"
            try:
                data = download(image.get("url") or image["thumbnail"])
                if args.apply:
                    insert_item(base_url, key, category, image, data, sort_order=taken)
                    seen.add(source)
                print(f"{'added' if args.apply else 'would add'} {label} ({len(data) // 1024} KB)")
                taken += 1
                total += 1
            except (ValueError, urllib.error.URLError, TimeoutError) as error:
                print(f"skip {label}: {error}", file=sys.stderr)
    print(f"{'Added' if args.apply else 'Would add'} {total} item(s).")


if __name__ == "__main__":
    main()
