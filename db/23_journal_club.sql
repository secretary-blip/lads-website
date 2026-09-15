-- =============================================================================
-- LADS PORTAL, STAGE 23: THE JOURNAL CLUB READING LIST
--
-- The club does not host papers. A row here is a pointer plus our own words:
-- the citation, a link out to the journal, and a summary written by whoever
-- presents it.
--
-- That summary is the point, not a courtesy line. A student without library
-- access will hit a paywall on the link, and the summary is what lets them
-- take part anyway. It also keeps LADS clear of redistributing anything it
-- has no right to redistribute.
--
-- Read is public for published rows, the same rule the activity archive uses.
-- The titles and dates are facts about what the Association is doing, and the
-- home page needs to show the next one without asking anybody to sign in.
-- Taking part is still members only; that is enforced by the portal, not here.
--
-- Run it in the SQL Editor. Safe to run more than once.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Who may edit the list
--
-- The Scientific Committee runs the club, but a committee head is a committee
-- head of one committee, and locking the list to a single committee_id would
-- break the first time the club changes hands. Any board role can edit, the
-- same call 18_media_admin.sql made for the archive.
-- -----------------------------------------------------------------------------
create or replace function public.can_manage_journal()
returns boolean
language sql stable security definer set search_path = public
as $$ select coalesce(
     (select role in ('committee_head','treasurer','executive','admin','super_admin')
        from public.profiles where id = auth.uid()), false) $$;

comment on function public.can_manage_journal() is
  'True for any board role. Governs writes to journal_papers.';

grant execute on function public.can_manage_journal() to authenticated;


-- -----------------------------------------------------------------------------
-- 2. The table
--
-- No status column. Whether a paper is next up or already discussed is a
-- comparison against today, and a stored status would be wrong the morning
-- after every session with nobody to notice.
-- -----------------------------------------------------------------------------
create table if not exists public.journal_papers (
  id          uuid primary key default gen_random_uuid(),
  session_on  date        not null,
  topic       text,
  title       text        not null,
  journal     text,
  pub_year    int,
  doi         text,
  url         text,
  summary     text,
  presenter   text,
  published   boolean     not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table  public.journal_papers is
  'One row per Journal Club session. The paper is linked, never stored.';
comment on column public.journal_papers.summary is
  'Our own summary, in our own words. Carries a student who cannot get past '
  'the publisher paywall, so it is required reading, not a caption.';
comment on column public.journal_papers.url is
  'Link out to the publisher or DOI resolver. LADS hosts no PDF.';
comment on column public.journal_papers.published is
  'False until the committee is ready to show it. Nothing unpublished is '
  'readable by anyone but the board.';

create index if not exists journal_papers_session_idx
  on public.journal_papers (session_on desc);

-- One session, one paper. Also stops a double-click in an editor creating two.
create unique index if not exists journal_papers_session_unique
  on public.journal_papers (session_on);


-- -----------------------------------------------------------------------------
-- 3. Keep updated_at honest
-- -----------------------------------------------------------------------------
create or replace function public.touch_journal_paper()
returns trigger language plpgsql
as $$ begin new.updated_at := now(); return new; end $$;

drop trigger if exists journal_papers_touch on public.journal_papers;
create trigger journal_papers_touch
  before update on public.journal_papers
  for each row execute function public.touch_journal_paper();


-- -----------------------------------------------------------------------------
-- 4. Row level security
--
-- Anonymous and signed-in visitors read published rows. The board reads and
-- writes everything. There is no policy letting a member write, deliberately:
-- the reading list is edited by whoever runs the club, not by its readers.
-- -----------------------------------------------------------------------------
alter table public.journal_papers enable row level security;

drop policy if exists journal_papers_public_read on public.journal_papers;
create policy journal_papers_public_read on public.journal_papers
  for select to anon, authenticated
  using (published);

drop policy if exists journal_papers_board_read on public.journal_papers;
create policy journal_papers_board_read on public.journal_papers
  for select to authenticated
  using (public.can_manage_journal());

drop policy if exists journal_papers_board_write on public.journal_papers;
create policy journal_papers_board_write on public.journal_papers
  for all to authenticated
  using (public.can_manage_journal())
  with check (public.can_manage_journal());

grant select on public.journal_papers to anon, authenticated;
grant insert, update, delete on public.journal_papers to authenticated;

notify pgrst, 'reload schema';
