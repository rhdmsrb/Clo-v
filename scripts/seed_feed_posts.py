#!/usr/bin/env python3
"""Seed the public feed with live Fit-Checks built from licensed outfit photos,
one occasion per post, crediting each photographer in the photo's description.

Sources (--source):
  pexels     Pexels API (default). Free licence, searched by photo content, so it
             returns real outfit photos. Needs PEXELS_API_KEY in the environment.
  openverse  Openverse (CC licences). Matches on captions, so results are often
             stock shots, museum displays or event photos: review them first.

A post has exactly 2 or 4 photos (the publish rule), stored at
fit-check-photos/<owner>/<post id>/<uuid>.jpg like the app does.

Keys are read from the environment, or from scripts/.env.local (KEY=VALUE lines,
gitignored; real environment variables take precedence).

Dry run by default: it searches, downloads and prints what it would create.
Writing needs --apply plus SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the
environment. The service-role key bypasses RLS: keep it out of the repo and
shell history.

The app caps voting windows at 24 hours, so seeded posts expire after
--expires-hours (default 24) and the feed empties again; re-run to refresh.

  python3 scripts/seed_feed_posts.py --owner <auth user uuid>
  python3 scripts/seed_feed_posts.py --owner <uuid> --list-only   # image URLs to review
  python3 scripts/seed_feed_posts.py --owner <uuid> --apply
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Reuse the wardrobe seeder's Openverse + Supabase helpers (same directory).
from seed_wardrobe_from_openverse import download, http_json, search, supabase_request, usable

ENV_FILE = Path(__file__).with_name(".env.local")  # gitignored via .env.*
BUCKET = "fit-check-photos"
PHOTOS_PER_POST = 2  # the app accepts 2 or 4
MAX_CREDIT_CHARS = 200
CANDIDATES_PER_SEARCH = 15  # many hits get skipped (wrong type, dead link), so ask for more than needed
CREATOR_FALLBACK = "Creator unknown"
PEXELS_URL = "https://api.pexels.com/v1/search"
PEXELS_LICENSE = "Pexels License"
PEXELS_HOME = "https://www.pexels.com/"
OPENVERSE_HOME = "https://openverse.org/"
# Photographers whose names contain one of these (case-insensitive) are skipped:
# red-carpet shots show public figures, not everyday outfits. Extend with --skip-creator.
BLOCKED_CREATOR_WORDS = ("celebrity",)

# Mirrors ExploreFilter.occasions; each entry is (caption, Pexels query, Openverse query).
OCCASIONS = {
    "Everyday": ("Easy everyday look. Thoughts?", "street style outfit casual", "street style outfit casual"),
    "Work": ("Office-ready. Would you wear this to work?", "business casual office outfit", "business casual woman"),
    "Date": ("Date night. Yes or no?", "date night outfit dress", "evening outfit woman dress"),
    "Interview": ("Interview fit. Does it read confident?", "professional suit blazer interview outfit", "job interview outfit"),
    "Party": ("Weekend party fit. Too much?", "party outfit night out", "party outfit night out"),
    "Travel": ("Travel day outfit. Comfy and put together?", "travel outfit casual jacket", "woman tourist outfit city"),
    "Wedding": ("Wedding guest look. Which one?", "wedding guest outfit dress", "wedding guest outfit dress"),
}


def pexels_candidates(query, api_key):
    """Pexels photos normalised to the Openverse result shape used below."""
    params = urllib.parse.urlencode({"query": query, "per_page": CANDIDATES_PER_SEARCH, "orientation": "portrait"})
    results = http_json(f"{PEXELS_URL}?{params}", {"Authorization": api_key}).get("photos", [])
    return [{
        "id": f"pexels-{photo['id']}",
        "url": photo["src"]["large"],
        "thumbnail": photo["src"]["medium"],
        "title": photo.get("alt") or f"Pexels photo {photo['id']}",
        "creator": photo.get("photographer"),
        "license": PEXELS_LICENSE,
        "foreign_landing_url": photo.get("url"),
    } for photo in results]


def openverse_candidates(query):
    return [image for image in search(query, CANDIDATES_PER_SEARCH) if usable(image)]


def credit_text(image):
    creator = (image.get("creator") or CREATOR_FALLBACK).replace("\n", " ").strip()[:60]
    version = f" {image['license_version']}" if image.get("license_version") else ""
    landing = image.get("foreign_landing_url") or OPENVERSE_HOME
    return f"Photo: {creator}, {image['license']}{version} ({landing})"[:MAX_CREDIT_CHARS]


def is_blocked_creator(image, blocked_words):
    creator = (image.get("creator") or "").lower()
    return any(word in creator for word in blocked_words)


def collect_photos(occasion, candidates, needed, seen_ids, blocked_words):
    """Downloads `needed` unseen, unblocked JPEGs for one occasion."""
    chosen = []
    for image in candidates:
        if len(chosen) == needed:
            break
        if image["id"] in seen_ids or is_blocked_creator(image, blocked_words):
            continue
        try:
            data = download(image.get("url") or image["thumbnail"])
        except (ValueError, urllib.error.URLError, TimeoutError) as error:
            print(f"skip [{occasion}] {image.get('title') or image['id']}: {error}", file=sys.stderr)
            continue
        seen_ids.add(image["id"])
        chosen.append((image, data))
    return chosen


def print_photo_urls(occasion, photos):
    print(f"[{occasion}]")
    for image, data in photos:
        print(f"  image:  {image.get('url') or image['thumbnail']}")
        print(f"  source: {image.get('foreign_landing_url') or OPENVERSE_HOME}")
        print(f"  credit: {credit_text(image)} ({len(data) // 1024} KB)")


def create_post(base_url, key, owner, occasion, caption, photos, expires_hours):
    post_id = str(uuid.uuid4())
    uploaded = []
    try:
        supabase_request("POST", f"{base_url}/rest/v1/fit_checks", key, json.dumps({
            "id": post_id, "creator_id": owner, "caption": caption, "occasion": occasion,
            "status": "draft", "is_public": True, "audience": "public",
        }).encode())
        for position, (image, data) in enumerate(photos, start=1):
            path = f"{owner}/{post_id}/{uuid.uuid4()}.jpg"  # lowercase: Storage RLS compares to auth.uid()::text
            supabase_request("POST", f"{base_url}/storage/v1/object/{BUCKET}/{path}", key, data, "image/jpeg")
            uploaded.append(path)
            supabase_request("POST", f"{base_url}/rest/v1/fit_check_photos", key, json.dumps({
                "fit_check_id": post_id, "image_url": path, "position": position,
                "description": credit_text(image),
            }).encode())
        now = datetime.now(timezone.utc)
        supabase_request("PATCH", f"{base_url}/rest/v1/fit_checks?id=eq.{post_id}", key, json.dumps({
            "status": "live", "created_at": now.isoformat(),
            "expires_at": (now + timedelta(hours=expires_hours)).isoformat(),
        }).encode())
    except (urllib.error.URLError, TimeoutError):
        # Don't leave a half-built post or orphaned files behind.
        for path in uploaded:
            supabase_request("DELETE", f"{base_url}/storage/v1/object/{BUCKET}/{path}", key)
        supabase_request("DELETE", f"{base_url}/rest/v1/fit_checks?id=eq.{post_id}", key)
        raise
    return post_id


def candidates_for(source, occasion, pexels_key):
    _, pexels_query, openverse_query = OCCASIONS[occasion]
    if source == "pexels":
        return pexels_candidates(pexels_query, pexels_key)
    return openverse_candidates(openverse_query)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--owner", required=True, help="auth.users id that will own the posts")
    parser.add_argument("--source", choices=("pexels", "openverse"), default="pexels")
    parser.add_argument("--occasions", nargs="+", choices=sorted(OCCASIONS), default=list(OCCASIONS))
    parser.add_argument("--expires-hours", type=int, default=24, help="how long the posts stay live (app max is 24)")
    parser.add_argument("--skip-creator", action="append", default=[], metavar="WORD",
                        help="also skip photographers whose name contains WORD (repeatable)")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="actually create posts (default: dry run)")
    mode.add_argument("--list-only", action="store_true",
                      help="print each chosen photo's image URL and source page so you can review them, then stop")
    return parser.parse_args()


def load_env_file(path):
    """Fills os.environ from KEY=VALUE lines. Real environment variables win, and empty values are ignored."""
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        name, separator, value = line.strip().partition("=")
        value = value.strip().strip("\"'")
        if separator and value and not name.startswith("#") and name.strip() not in os.environ:
            os.environ[name.strip()] = value


def main():
    load_env_file(ENV_FILE)
    args = parse_args()
    owner = str(uuid.UUID(args.owner))  # validates and lowercases
    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    pexels_key = os.environ.get("PEXELS_API_KEY", "")
    if args.apply and not (base_url.startswith("https://") and key):
        sys.exit("--apply needs SUPABASE_URL (https) and SUPABASE_SERVICE_ROLE_KEY in the environment.")
    if args.source == "pexels" and not pexels_key:
        sys.exit("--source pexels needs PEXELS_API_KEY in the environment (free key: pexels.com/api).")

    blocked_words = BLOCKED_CREATOR_WORDS + tuple(word.lower() for word in args.skip_creator)
    seen_ids, created = set(), 0
    for occasion in args.occasions:
        caption = OCCASIONS[occasion][0]
        try:
            candidates = candidates_for(args.source, occasion, pexels_key)
        except urllib.error.HTTPError as error:
            sys.exit(f"{args.source} search failed for [{occasion}]: HTTP {error.code} {error.reason}")
        photos = collect_photos(occasion, candidates, PHOTOS_PER_POST, seen_ids, blocked_words)
        if len(photos) < PHOTOS_PER_POST:
            print(f"skip [{occasion}]: found {len(photos)} of {PHOTOS_PER_POST} usable photos", file=sys.stderr)
            continue
        if args.list_only:
            print_photo_urls(occasion, photos)
            created += 1
            continue
        summary = "; ".join(f"{credit_text(image)} ({len(data) // 1024} KB)" for image, data in photos)
        if args.apply:
            post_id = create_post(base_url, key, owner, occasion, caption, photos, args.expires_hours)
            print(f"created {post_id} [{occasion}] \"{caption}\" <- {summary}")
        else:
            print(f"would create [{occasion}] \"{caption}\" <- {summary}")
        created += 1
    verb = "Created" if args.apply else "Listed" if args.list_only else "Would create"
    print(f"{verb} {created} post(s).")


if __name__ == "__main__":
    main()
