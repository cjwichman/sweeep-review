# Load a Qualtrics abstract export into sweeep.abstracts.
# Requires the service-role key. Keep the key out of version control.

library(data.table)
library(httr2)
library(jsonlite)

SUPABASE_URL <- Sys.getenv("SUPABASE_URL")
SERVICE_KEY  <- Sys.getenv("SUPABASE_SERVICE_KEY")

# Sys.getenv returns an empty string for anything unset, which otherwise fails
# much later with an unhelpful curl error about a missing host.
if (!nzchar(SUPABASE_URL) || !nzchar(SERVICE_KEY)) {
  stop("Set SUPABASE_URL and SUPABASE_SERVICE_KEY in ~/.Renviron, then restart R.")
}
SUPABASE_URL <- sub("/+$", "", SUPABASE_URL)

# Legacy service_role keys are JWTs and PostgREST reads the role from the
# Authorization header, so apikey alone falls back to anon and is refused. The
# newer sb_secret_ keys travel on apikey and are rejected in a bearer header.
auth_headers <- function(key) {
  h <- list(apikey = key)
  if (!grepl("^sb_", key)) h$Authorization <- paste("Bearer", key)
  h
}

# Local path to the Qualtrics export. Kept outside the repository, since the
# file carries submitter names, addresses, and unpublished abstracts.
csv_path <- path.expand(Sys.getenv("ABSTRACTS_CSV"))

if (!nzchar(csv_path) || !file.exists(csv_path)) stop("Set ABSTRACTS_CSV to the export path.")

# Qualtrics writes three header rows: variable names, question text, and an
# import-id block. Read the first as names and drop the other two.
raw <- fread(csv_path, header = TRUE, skip = 0, colClasses = "character")
raw <- raw[-(1:2)]

map <- c(
  response_id    = "ResponseId",
  submitter      = "Q3",
  email          = "Q4",
  affiliation    = "Q18",
  role_choice    = "Q8",
  role_other     = "Q8_5_TEXT",
  interest       = "Q6",
  organizer_note = "Q9",
  title          = "Q12",
  coauthors      = "Q13",
  body           = "Q15",
  eggtimer_ok    = "Q17",
  status         = "Status",
  submitted_at   = "RecordedDate"
)

d <- raw[, ..map]
setnames(d, names(map))

# ------------------------------------------------------------------ cleaning

# Test responses generated while building the form.
d <- d[status == "IP Address"]

# Attendance-only responses and abandoned partials carry no abstract.
d <- d[trimws(body) != "" & trimws(title) != ""]

# Several people submitted twice, usually an abandoned attempt followed by a
# complete one, and one person resubmitted a minute later with a corrected
# title. Keep the most recent complete submission per address.
d[, submitted_at := as.POSIXct(submitted_at, tz = "UTC")]
setorder(d, email, -submitted_at)
d <- unique(d, by = "email")

# ------------------------------------------------------------------ recoding

# Track comes from the submitter's own selection in Q6, not a separate screen.
# Anyone requesting a full presentation is reviewed in the full track, since
# the egg-timer fallback in Q17 handles the demotion case.
d[, track := fifelse(grepl("full presentation", interest, fixed = TRUE), "full", "egg")]

d[, role := fifelse(role_choice == "Other" & trimws(role_other) != "",
                    role_other, role_choice)]
d[, eggtimer_ok := eggtimer_ok == "Yes"]
d[, word_count := lengths(strsplit(trimws(body), "\\s+"))]

keep <- c("response_id", "track", "title", "submitter", "email", "affiliation",
          "role", "coauthors", "body", "word_count", "eggtimer_ok",
          "organizer_note", "submitted_at")
d <- d[, ..keep]

stopifnot(
  all(d$track %in% c("full", "egg")),
  !anyDuplicated(d$response_id),
  nrow(d) > 0
)

# ------------------------------------------------------------------- checks
# Flags for manual review before the committee sees the list. None of these
# block the load.

cat("Submissions loaded:", nrow(d), "\n")
print(d[, .N, by = track])

phd_full <- d[track == "full" & grepl("Ph.D", role, fixed = TRUE)]
if (nrow(phd_full)) {
  cat("\nPh.D. students requesting a full slot (full talks are faculty and post-doc only):\n")
  print(phd_full[, .(submitter, affiliation, title)])
}

over <- d[word_count > 250]
if (nrow(over)) {
  cat("\nAbstracts over the 250-word limit:\n")
  print(over[, .(submitter, word_count)])
}

notes <- d[trimws(organizer_note) != ""]
if (nrow(notes)) cat("\nSubmissions with a note to the organizers:", nrow(notes), "\n")

# --------------------------------------------------------------------- load
# merge-duplicates on response_id makes the load re-runnable after a correction.

batches <- split(d, ceiling(seq_len(nrow(d)) / 50))

for (b in batches) {
  resp <- request(paste0(SUPABASE_URL, "/rest/v1/abstracts")) |>
    req_method("POST") |>
    req_headers(!!!auth_headers(SERVICE_KEY)) |>
    req_headers(
      `Content-Type`    = "application/json",
      `Content-Profile` = "sweeep",
      Prefer            = "resolution=merge-duplicates"
    ) |>
    req_body_raw(toJSON(b, auto_unbox = TRUE, POSIXt = "ISO8601", na = "null")) |>
    req_error(is_error = function(r) FALSE) |>
    req_perform()

  if (resp_status(resp) >= 300) {
    stop("Upload failed with HTTP ", resp_status(resp), ": ", resp_body_string(resp))
  }
}

cat("\nUpload complete.\n")
