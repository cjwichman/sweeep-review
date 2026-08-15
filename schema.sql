-- Abstract review backend.
-- Runs inside a Supabase project shared with other applications. Everything
-- lives in the `sweeep` schema. Nothing is created in `public`.

create schema if not exists sweeep;

grant usage on schema sweeep to authenticated, service_role;

-- ---------------------------------------------------------------- tables

-- Reviewers are provisioned by hand. The project's auth.users table is shared
-- with other applications, so authentication alone grants nothing. Membership
-- in this table is what every policy below tests.
create table if not exists sweeep.reviewers (
  id            uuid primary key references auth.users (id) on delete cascade,
  email         text not null,
  display_name  text not null,
  is_admin      boolean not null default false
);

create table if not exists sweeep.abstracts (
  id            bigint generated always as identity primary key,
  response_id   text unique,                    -- Qualtrics ResponseId
  track         text not null check (track in ('full', 'egg')),
  title         text not null,
  submitter     text,
  email         text,
  affiliation   text,
  role          text,                           -- Q8, with Q8_5_TEXT folded in
  coauthors     text,
  body          text not null,
  word_count    integer,
  eggtimer_ok   boolean,                        -- Q17 fallback if not given a full slot
  organizer_note text,                          -- Q9, comments to the organizers
  submitted_at  timestamptz
);

create index if not exists abstracts_track_idx on sweeep.abstracts (track, id);

-- One row per reviewer per abstract. The private score and note.
create table if not exists sweeep.reviews (
  reviewer_id   uuid   not null references sweeep.reviewers (id) on delete cascade,
  abstract_id   bigint not null references sweeep.abstracts (id) on delete cascade,
  score         smallint check (score between 1 and 5),
  -- Personal ordering within a track, ascending, best first. Sparse floats so a
  -- drag rewrites one row instead of the whole list. Null until the reviewer
  -- opens the list view and reorders something.
  position      double precision,
  comment       text,
  updated_at    timestamptz not null default now(),
  primary key (reviewer_id, abstract_id)
);

-- Discussion thread, separate from the private review note. Follows the same
-- reveal flag so nothing leaks during blind scoring.
create table if not exists sweeep.discussion (
  id            bigint generated always as identity primary key,
  abstract_id   bigint not null references sweeep.abstracts (id) on delete cascade,
  author_id     uuid   not null references sweeep.reviewers (id) on delete cascade,
  body          text not null check (length(trim(body)) > 0),
  created_at    timestamptz not null default now()
);

create index if not exists discussion_abstract_idx
  on sweeep.discussion (abstract_id, created_at);

create table if not exists sweeep.app_settings (
  id              smallint primary key default 1 check (id = 1),
  reviews_visible boolean not null default false
);

insert into sweeep.app_settings (id) values (1) on conflict do nothing;

-- ------------------------------------------------------- updated_at trigger

create or replace function sweeep.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists reviews_touch on sweeep.reviews;
create trigger reviews_touch
  before update on sweeep.reviews
  for each row execute function sweeep.touch_updated_at();

-- --------------------------------------------------------- helper functions
-- security definer so policies read these tables without recursing through the
-- policies currently being evaluated.

create or replace function sweeep.is_reviewer()
returns boolean language sql security definer stable
set search_path = sweeep, public as $$
  select exists (select 1 from sweeep.reviewers where id = auth.uid());
$$;

create or replace function sweeep.is_admin()
returns boolean language sql security definer stable
set search_path = sweeep, public as $$
  select coalesce((select is_admin from sweeep.reviewers where id = auth.uid()), false);
$$;

create or replace function sweeep.reviews_unlocked()
returns boolean language sql security definer stable
set search_path = sweeep, public as $$
  select coalesce((select reviews_visible from sweeep.app_settings where id = 1), false);
$$;

-- ------------------------------------------------------------------- RLS
-- The anon key is public by design and grants nothing on its own. Access
-- requires a session whose uid resolves to a row in sweeep.reviewers.

alter table sweeep.reviewers    enable row level security;
alter table sweeep.abstracts    enable row level security;
alter table sweeep.reviews      enable row level security;
alter table sweeep.discussion   enable row level security;
alter table sweeep.app_settings enable row level security;

grant select, insert, update, delete
  on sweeep.reviews, sweeep.discussion to authenticated;
grant select on sweeep.reviewers, sweeep.abstracts to authenticated;
grant select, update on sweeep.app_settings to authenticated;
grant usage, select on all sequences in schema sweeep to authenticated;

-- service_role bypasses RLS but still needs table and schema grants. Used by
-- load_abstracts.R and nothing else. anon is granted nothing anywhere, so an
-- unauthenticated caller cannot reach these tables at all.
grant all on all tables in schema sweeep to service_role;
grant all on all sequences in schema sweeep to service_role;
alter default privileges in schema sweeep grant all on tables to service_role;
alter default privileges in schema sweeep grant all on sequences to service_role;

-- Reviewer names label the dashboard, so the roster is readable by the
-- committee. Nothing beyond name and email sits in the table.
drop policy if exists reviewers_read on sweeep.reviewers;
create policy reviewers_read on sweeep.reviewers
  for select using (sweeep.is_reviewer());

drop policy if exists abstracts_read on sweeep.abstracts;
create policy abstracts_read on sweeep.abstracts
  for select using (sweeep.is_reviewer());

drop policy if exists abstracts_write on sweeep.abstracts;
create policy abstracts_write on sweeep.abstracts
  for all using (sweeep.is_admin()) with check (sweeep.is_admin());

-- Own reviews always. Everyone else's only after the reveal.
drop policy if exists reviews_read on sweeep.reviews;
create policy reviews_read on sweeep.reviews
  for select using (
    reviewer_id = auth.uid() or sweeep.reviews_unlocked() or sweeep.is_admin()
  );

drop policy if exists reviews_write on sweeep.reviews;
create policy reviews_write on sweeep.reviews
  for all using (reviewer_id = auth.uid())
  with check (reviewer_id = auth.uid() and sweeep.is_reviewer());

drop policy if exists discussion_read on sweeep.discussion;
create policy discussion_read on sweeep.discussion
  for select using (
    author_id = auth.uid() or sweeep.reviews_unlocked() or sweeep.is_admin()
  );

drop policy if exists discussion_write on sweeep.discussion;
create policy discussion_write on sweeep.discussion
  for insert with check (author_id = auth.uid() and sweeep.is_reviewer());

drop policy if exists discussion_delete on sweeep.discussion;
create policy discussion_delete on sweeep.discussion
  for delete using (author_id = auth.uid() or sweeep.is_admin());

drop policy if exists settings_read on sweeep.app_settings;
create policy settings_read on sweeep.app_settings
  for select using (sweeep.is_reviewer());

drop policy if exists settings_write on sweeep.app_settings;
create policy settings_write on sweeep.app_settings
  for update using (sweeep.is_admin()) with check (sweeep.is_admin());

-- --------------------------------------------------------- provisioning
-- The committee is defined by email before anyone signs in. Seats are claimed
-- on first sign-in, which is also where the reviewer supplies their own name.
-- Nothing here requires looking up a uid by hand.

create table if not exists sweeep.invitees (
  email     text primary key,
  is_admin  boolean not null default false
);

alter table sweeep.invitees enable row level security;
-- No policy. The allowlist is readable only through the definer function below.

-- Insert the committee, one row per address:
--
--   insert into sweeep.invitees (email, is_admin) values
--     ('organizer@example.edu', true),
--     ('reviewer@example.edu',  false)
--   on conflict (email) do nothing;

-- Claims a seat for the signed-in user if their address is on the allowlist.
-- Re-running updates the display name, so reviewers can rename themselves.
create or replace function sweeep.claim_seat(name text)
returns sweeep.reviewers language plpgsql security definer
set search_path = sweeep, public as $$
declare
  addr text := lower(auth.jwt() ->> 'email');
  adm  boolean;
  out  sweeep.reviewers;
begin
  select i.is_admin into adm from sweeep.invitees i where lower(i.email) = addr;
  if not found then
    raise exception 'Address % is not on the committee list.', addr;
  end if;

  insert into sweeep.reviewers (id, email, display_name, is_admin)
  values (auth.uid(), addr,
          coalesce(nullif(trim(name), ''), split_part(addr, '@', 1)), adm)
  on conflict (id) do update
    set display_name = excluded.display_name,
        is_admin     = excluded.is_admin
  returning * into out;

  return out;
end;
$$;

grant execute on function sweeep.claim_seat(text) to authenticated;
