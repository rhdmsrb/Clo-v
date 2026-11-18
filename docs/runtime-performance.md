# Runtime performance

## On-device measurements

Use a Release build and the same iPhone, account, feed fixture and network
profile for before-and-after runs. Measure signed-in cold launch and a refresh
with the image cache already warm. Capture the median and p95 of each scenario
separately. Include a constrained network profile to expose round trips.

In Instruments, record signposts from subsystem `com.clov.app` and category
`runtime`. The interval between **App state initialized** and **First home
photo displayed** measures time to the first post's image on a signed-in
launch. **Profile load** and **Home feed first page** show where that time was
spent. **Remote image load** measures cache-miss latency including decode.
**Image network bytes** records response body bytes for network loads only.

Use Instruments' network trace to count PostgREST and Storage requests and
check which photos start downloading before the first image appears. Record
the peak memory of a fixed-length scroll through Home and Explore.

## Server checks

In staging, verify that `home_feed_page_v1` uses one PostgREST request and at
most one Storage signing request for a normal 24-post page. Group previews
request at most 32 groups per RPC and sign up to three representative photos
per group. Test a cold load, pull to refresh, two-page scroll with a concurrent
new post, and vote/undo from Home. Include each supported audience and a
blocked account in the fixture. Run the local SQL tests against the snapshot
before testing PostgREST and Storage in staging.

Compare query calls, total execution time and mean execution time in
`pg_stat_statements`. Use staging query plans with realistic data volume
and the authenticated role to verify cursor and group index use. Track
Storage errors and both database calls and bytes per visited feed page when
comparing builds.
