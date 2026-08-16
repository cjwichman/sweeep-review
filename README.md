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

Each reviewer writes one note per abstract alongside the score. Notes follow the
same flag as scores.

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

## Reading order

Each reviewer sees the abstracts in a different order, so queue position is not
a bias shared across the committee. The order is a hash of the reviewer id and
the abstract id rather than a random draw, which means it is stable for a given
reviewer across sessions and devices. Nothing about the order is stored.

The index numbers in the sidebar are positions in that reviewer's own queue and
do not correspond between reviewers. The dashboard is unaffected, since every
aggregation is order-independent.

## Personal ordering

The list view shows every abstract in the current track as one row, sorted by
score until the reviewer moves something. The first move assigns a position to
every abstract in that track, and subsequent moves rewrite one row using the
midpoint between its new neighbours. Scores can be set inline from the list
without opening the abstract.

Rows are dragged on a desktop browser. Touch devices do not fire HTML5 drag
events, so each row also carries up and down arrows, shown on narrow screens.
Both paths call the same reordering code.

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

## Decisions and notification

Four outcomes. Full is a 20-minute presentation. Short is 10 minutes, for
faculty and post-docs. Egg-timer is 10 minutes, for Ph.D. students. The fourth
is reject.

Once scoring closes, the dashboard records the outcome. Set from bar applies the
current slider position across the track in one pass. In the full track, anyone
above the bar takes a full slot, and below it anyone who accepted the fallback
moves to a short presentation while the rest are rejected. In the egg track the
bar splits accept from reject. Decisions already recorded by hand are left alone, so
the bulk pass can be run first and adjusted afterwards, or the other way round.

Per-row buttons set full, short, egg, reject, or clear the decision. Accepted rows carry
a coloured edge, rejected titles are struck through, and a panel counts the three
outcomes and what remains undecided.

Export CSV writes one row per abstract across both tracks, carrying the contact
details, the requested track, the fallback flag, every aggregate, the individual
scores, the notes, and the decision. That file is the mail merge source.

`draft_notifications.R` reads it and writes one letter per recipient into a
`notifications` directory, plus a single file containing all letters for review
and an address list per outcome. Nothing is sent.

Five templates, one per outcome plus the two rejection variants. Acceptances are
addressed by name.
Rejections are addressed to "colleague" and are identical within a group, so one
blind-copied message per group covers them, which is what `_address_lists.csv`
is for.

Acceptance wording follows the outcome. Rejection wording follows the requested
track, so a faculty submission turned down after requesting a full slot gets the
general rejection rather than the one explaining Ph.D. student egg-timer
competition.

The short and egg-timer letters are separate because only the egg-timer track
carries the Ph.D. student framing and the travel funding paragraph.

The registration link, website, contact address, and subject line are constants
at the top of the script and change each year. The egg-timer slot count quoted
in the rejection is counted from the decisions rather than hardcoded.

## Keyboard

- `j` / `k` or arrows — next, previous
- `1`–`5` — score, pressing the current score clears it
- `c` — jump to the private note
- `Esc` — leave a text box
