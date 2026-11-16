#!/usr/bin/env python3
"""Fetch openly licensed clothing photos from Openverse and add them to one
user's wardrobe in Supabase (Storage upload + wardrobe_items row), crediting
the photographer the same way the app's clothing catalog does.

Dry run by default: it searches and prints what it would upload. Writing needs
--apply plus SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.
The service-role key bypasses RLS: keep it out of the repo and shell history.

  python3 scripts/seed_wardrobe_from_openverse.py --owner <auth user uuid>
  python3 scripts/seed_wardrobe_from_openverse.py --owner <uuid> --apply
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

OPENVERSE_URL = "https://api.openverse.org/v1/images/"
USER_AGENT = "CLO-V seed script"
LICENSES = "cc0,pdm,by,by-sa"
BUCKET = "wardrobe-items"
MAX_IMAGE_BYTES = 10 * 1024 * 1024  # bucket file-size limit
REQUEST_TIMEOUT_SECONDS = 30

# Mirrors CatalogCategory in ClothingCatalogView.swift.
CATEGORIES = {
    "dress": "woman wearing dress",
    "top": "women's blouse shirt clothing",
    "bottom": "woman wearing jeans",
    "outerwear": "women wearing coat jacket",
    "shoes": "women shoes product fashion",
    "accessory": "women handbag accessories fashion",
}


def http_json(url, headers=None):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        return json.load(response)


def search(query, count):
    params = urllib.parse.urlencode({"q": query, "license": LICENSES, "page_size": min(count * 3, 20), "mature": "false"})
    return http_json(f"{OPENVERSE_URL}?{params}").get("results", [])


def credit_tag(image):
    creator = (image.get("creator") or "Creator unknown").replace("|", " ")
    version = f" {image['license_version']}" if image.get("license_version") else ""
    return "|".join([
        f"Photo credit: {creator}",
        f"{image['license'].upper()}{version}",
        image.get("license_url") or "https://creativecommons.org/",
        image.get("foreign_landing_url") or "https://openverse.org/",
    ])


def usable(image):
    url = image.get("url") or image.get("thumbnail") or ""
    return url.startswith("https://") and bool(image.get("creator") or image["license"] in ("cc0", "pdm"))


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
        content_type = response.headers.get_content_type()
        data = response.read(MAX_IMAGE_BYTES + 1)
    if content_type != "image/jpeg" or len(data) > MAX_IMAGE_BYTES:
        raise ValueError(f"skipped ({content_type}, {len(data)} bytes)")
    return data


def supabase_request(method, url, key, body=None, content_type="application/json"):
    headers = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": content_type, "Prefer": "return=minimal"}
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS):
        pass


def upload_item(base_url, key, owner, category, image, data):
    item_id = str(uuid.uuid4())
    path = f"{owner}/{item_id}/{uuid.uuid4()}.jpg"  # lowercase: Storage RLS compares to auth.uid()::text
    supabase_request("POST", f"{base_url}/storage/v1/object/{BUCKET}/{path}", key, data, "image/jpeg")
    row = {
        "id": item_id,
        "owner_id": owner,
        "image_url": path,
        "name": (image.get("title") or "").split(" / ")[0].strip()[:55] or None,
        "category": category,
        "tags": [credit_tag(image)],
    }
    try:
        supabase_request("POST", f"{base_url}/rest/v1/wardrobe_items", key, json.dumps(row).encode())
    except urllib.error.URLError:
        supabase_request("DELETE", f"{base_url}/storage/v1/object/{BUCKET}/{path}", key)  # don't orphan the file
        raise
    return item_id


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--owner", required=True, help="auth.users id that will own the wardrobe items")
    parser.add_argument("--per-category", type=int, default=3)
    parser.add_argument("--categories", nargs="+", choices=sorted(CATEGORIES), default=sorted(CATEGORIES))
    parser.add_argument("--apply", action="store_true", help="actually upload (default: dry run)")
    args = parser.parse_args()

    owner = str(uuid.UUID(args.owner))  # validates and lowercases
    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    if args.apply and not (base_url.startswith("https://") and key):
        sys.exit("--apply needs SUPABASE_URL (https) and SUPABASE_SERVICE_ROLE_KEY in the environment.")

    uploaded = 0
    for category in args.categories:
        taken = 0
        for image in search(CATEGORIES[category], args.per_category):
            if taken >= args.per_category:
                break
            if not usable(image):
                continue
            label = f"[{category}] {image.get('title') or image['id']} - {image['license'].upper()} - {image.get('creator') or 'unknown'}"
            try:
                data = download(image.get("url") or image["thumbnail"])
                if not args.apply:
                    print(f"would upload {label} ({len(data) // 1024} KB)")
                else:
                    upload_item(base_url, key, owner, category, image, data)
                    print(f"uploaded {label}")
                taken += 1
                uploaded += 1
            except (ValueError, urllib.error.URLError, TimeoutError) as error:
                print(f"skip {label}: {error}", file=sys.stderr)
    print(f"{'Uploaded' if args.apply else 'Would upload'} {uploaded} item(s).")


if __name__ == "__main__":
    main()
