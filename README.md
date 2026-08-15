# Abstract review

Conference abstract review for a small program committee. Static frontend on
GitHub Pages, Postgres and auth on Supabase. Submission text and reviewer scores
live in the database and never enter the repository.

## Files

- `config.js` — Supabase URL, anon key, shared client pinned to the `sweeep` schema
- `schema.sql` — tables, row-level security, helper functions
- `index.html` — reviewer application
- `dashboard.html` — rankings, aggregations, acceptance bar
- `load_abstracts.R` — Qualtrics export to Supabase

## Shared project

The Supabase project also hosts amend.city. Two consequences:

1. Every object lives in the `sweeep` schema. Nothing is created in `public`.
   The schema must be listed under Settings → API → Exposed schemas, and the
   client sets `db: { schema: 'sweeep' }`. Requests return empty otherwise.
2. `auth.users` is shared across applications. Authentication grants nothing on
   its own. Every policy tests membership in `sweeep.reviewers`, and a row is
   created only by `sweeep.claim_seat()`, which checks the signed-in address
   against `sweeep.invitees`. An amend.city account cannot self-provision.

## Setup

1. Run `schema.sql` in the SQL editor.
2. Authentication → URL Configuration → add the Pages URL to the redirect allow
   list.
3. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` in `config.js`. The anon key is
   public by design. Row-level security is what protects the data.
4. Create six accounts under Authentication -> Users -> Add user, one per login
   address in `config.js`, all sharing one password, with Auto Confirm User on.
   Then run the reviewer insert at the bottom of `schema.sql`, and turn off
   public signups under Authentication -> Sign In / Providers.
5. Push to a repo, enable Pages, distribute the URL.

## Verify before distributing

Two checks, both run from R. The first confirms the schema is reachable, the
second confirms the data is not.

```r
library(httr2)

url  <- Sys.getenv("SUPABASE_URL")
anon <- Sys.getenv("SUPABASE_ANON_KEY")

check <- function(table) {
  resp <- request(paste0(url, "/rest/v1/", table, "?select=*&limit=5")) |>
    req_headers(apikey = anon, `Accept-Profile` = "sweeep") |>
    req_error(is_error = function(r) FALSE) |>
    req_perform()
  cat(table, resp_status(resp), resp_body_string(resp), "\n")
}

check("abstracts")
check("reviews")
```

Either of two results is correct. HTTP 403 with code 42501, permission denied
for schema sweeep, means the anon role holds no grant on the schema and the
request is refused before row-level security is consulted. HTTP 200 with an
empty array means anon can reach the schema and RLS refused the read. Both are
safe. The 403 is what this schema produces, since anon is granted nothing.

Status 404 means the schema is not listed under Exposed schemas. Rows in the
body mean the abstracts are world-readable, which is the one outcome that must
be fixed before the link goes out.

Also open the Pages URL in a private browser window. The sign-in card should
appear and no abstract text should be visible anywhere on the page.

## Blind review and the reveal

`sweeep.app_settings.reviews_visible` is false by default. While false, each
reviewer sees only their own scores, private notes, and discussion comments.
The Admin control flips the flag once scoring closes, at which point the full
set becomes visible and the dashboard unlocks. Enforcement is in the RLS
policies, not the client, so querying the API directly does not bypass it.

Discussion comments are gated by the same flag. Reviewers can post during blind
scoring, but nothing appears to others until the reveal. To let discussion run
in the open from the start, change the `discussion_read` policy to
`using (sweeep.is_reviewer())`.

## Loading abstracts

`load_abstracts.R` maps the Qualtrics export and posts it to `sweeep.abstracts`.
Column mapping is at the top of the script and changes with the survey. Four
cleaning steps run before upload:

| Step | Purpose |
| --- | --- |
| Drop survey previews | removes responses generated while building the form |
| Drop rows with no title or abstract | removes attendance-only and abandoned partials |
| Keep the latest submission per email | some people submit more than once |
| Derive track from the presentation-type question | assigns the tranche |

Track comes from the submitter's own selection, not from role and not from a
separate screen. Anyone requesting a full presentation lands in the full track.

The form also asks whether a full-talk submitter would accept a short slot
instead. That answer drives the demotion path, since the short-talk program is
assembled by hand after the full bar is set, drawing from the short-talk list
and from full requests that fell below the bar. Three places surface the flag: a
tag under the byline in the review pane, a marker in the list view, and a marker
plus a Demotable count on the dashboard, which reports how many below-the-bar
full requests accepted a demotion at the current bar.

The script prints three checks before uploading, none of which block the load.
Submitters requesting a slot their role is not eligible for are flagged.
Abstracts over the word limit are listed. The count of submissions carrying a
note to the organizers is reported.

## Personal ordering

The list view shows every abstract in the current track as one row, sorted by
score until the reviewer drags something. The first drag assigns a position to
every abstract in that track, and subsequent drags rewrite one row using the
midpoint between its new neighbours. Scores can be set inline from the list
without opening the abstract.

Positions feed the Pctile column and nothing else. A reviewer with a complete
manual order contributes a strict ranking. A reviewer who never opened the list
view contributes midranks over their scores, which leaves genuine ties intact.
Both are on a zero-to-one scale, so the two kinds of reviewer average together
without weighting. The reviewer table on the dashboard reports who supplied an
order.

Nothing needs finalizing. Positions are written as they change, and revealing
reviews is what freezes the inputs.

The separation is deliberate. Mean, Z-mean, median, and min read the 1-5 scores.
Pctile reads positions. An abstract scored a 4 but dragged to the bottom of a
reviewer's list will disagree across those columns and pick up the tilde flag,
which is the case worth committee time.

## Keyboard

- `j` / `k` or arrows — next, previous
- `1`–`5` — score, pressing the current score clears it
- `c` — jump to the private note
- `Esc` — leave a text box
