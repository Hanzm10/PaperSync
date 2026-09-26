-- PaperSync cloud copy of notebooks, pages, strokes, and recognized page text.
-- Each row is private to its owner. The phone keeps a local copy and upserts here
-- when the user is signed in. Ids are generated on the device.

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon;
grant execute on function private.set_updated_at() to authenticated, service_role;

create table public.notebooks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  -- Dart ARGB. Black is 0xFF000000, which does not fit in a 32-bit integer.
  ink_color bigint not null default 4278190080,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint notebooks_name_not_blank check (char_length(btrim(name)) > 0),
  constraint notebooks_id_user_id_key unique (id, user_id)
);

comment on table public.notebooks is
  'A paper notebook. Inbox is a normal notebook the app creates by name.';
comment on column public.notebooks.ink_color is
  'Default ink for new strokes, as a Dart ARGB integer. Black is 4278190080 (0xFF000000).';

create table public.pages (
  id uuid primary key default gen_random_uuid(),
  notebook_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  page_index integer not null,
  captured_at timestamptz not null default now(),
  paper_rect jsonb not null default '{"originXMm":0,"originYMm":0,"widthMm":170,"heightMm":107,"rotationDeg":0}'::jsonb,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint pages_page_index_nonnegative check (page_index >= 0),
  constraint pages_paper_rect_object check (jsonb_typeof(paper_rect) = 'object'),
  constraint pages_id_user_id_key unique (id, user_id),
  constraint pages_notebook_user_fkey
    foreign key (notebook_id, user_id)
    references public.notebooks (id, user_id)
    on delete cascade
);

comment on table public.pages is
  'One physical sheet. page_index orders sheets inside a notebook.';
comment on column public.pages.paper_rect is
  'Tablet millimeters mapped onto the page: originXMm, originYMm, widthMm, heightMm, rotationDeg. Default is the 170 by 107 mm active area.';

create table public.strokes (
  id uuid primary key default gen_random_uuid(),
  page_id uuid not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  points jsonb not null,
  color bigint not null default 4278190080,
  width double precision not null default 1,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint strokes_points_array check (jsonb_typeof(points) = 'array'),
  constraint strokes_version_positive check (version >= 1),
  constraint strokes_width_positive check (width > 0),
  constraint strokes_page_user_fkey
    foreign key (page_id, user_id)
    references public.pages (id, user_id)
    on delete cascade
);

comment on table public.strokes is
  'One pen stroke. Edits bump version. A higher version wins; updated_at breaks ties. Erase sets deleted_at.';
comment on column public.strokes.points is
  'JSON array of {x, y, p, t}: millimeters, pressure, and tMs.';
comment on column public.strokes.color is
  'Ink color as a Dart ARGB integer. The UI uses black, blue, and red.';

create table public.page_text (
  page_id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  text text not null default '',
  tsv tsvector generated always as (to_tsvector('english', text)) stored,
  updated_at timestamptz not null default now(),
  constraint page_text_page_user_fkey
    foreign key (page_id, user_id)
    references public.pages (id, user_id)
    on delete cascade
);

comment on table public.page_text is
  'Recognized handwriting for one page, so search works on another device.';

create index notebooks_user_updated_idx
  on public.notebooks (user_id, updated_at);

create index pages_notebook_user_idx
  on public.pages (notebook_id, user_id);

create unique index pages_live_page_index_idx
  on public.pages (notebook_id, page_index)
  where deleted_at is null;

create index pages_user_updated_idx
  on public.pages (user_id, updated_at);

create index strokes_page_user_idx
  on public.strokes (page_id, user_id);

create index strokes_user_updated_idx
  on public.strokes (user_id, updated_at);

create index page_text_page_user_idx
  on public.page_text (page_id, user_id);

create index page_text_user_updated_idx
  on public.page_text (user_id, updated_at);

create index page_text_tsv_idx
  on public.page_text using gin (tsv);

create trigger notebooks_set_updated_at
  before update on public.notebooks
  for each row execute function private.set_updated_at();

create trigger pages_set_updated_at
  before update on public.pages
  for each row execute function private.set_updated_at();

create trigger strokes_set_updated_at
  before update on public.strokes
  for each row execute function private.set_updated_at();

create trigger page_text_set_updated_at
  before update on public.page_text
  for each row execute function private.set_updated_at();

alter table public.notebooks enable row level security;
alter table public.pages enable row level security;
alter table public.strokes enable row level security;
alter table public.page_text enable row level security;

-- Default privileges grant everything, including truncate, which ignores RLS.
revoke all on table public.notebooks from anon, authenticated, public;
revoke all on table public.pages from anon, authenticated, public;
revoke all on table public.strokes from anon, authenticated, public;
revoke all on table public.page_text from anon, authenticated, public;

grant select, insert, update, delete on table public.notebooks to authenticated, service_role;
grant select, insert, update, delete on table public.pages to authenticated, service_role;
grant select, insert, update, delete on table public.strokes to authenticated, service_role;
grant select, insert, update, delete on table public.page_text to authenticated, service_role;

create policy notebooks_owner
  on public.notebooks
  for all
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy pages_owner
  on public.pages
  for all
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy strokes_owner
  on public.strokes
  for all
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);

create policy page_text_owner
  on public.page_text
  for all
  to authenticated
  using ((select auth.uid()) is not null and (select auth.uid()) = user_id)
  with check ((select auth.uid()) is not null and (select auth.uid()) = user_id);
