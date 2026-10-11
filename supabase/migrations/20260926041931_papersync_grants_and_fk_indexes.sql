-- Tighten table privileges and cover composite foreign keys.
-- Safe to run after the initial schema, including on a database that already
-- received the tighter grants and the composite indexes.

revoke all on table public.notebooks from anon, authenticated, public;
revoke all on table public.pages from anon, authenticated, public;
revoke all on table public.strokes from anon, authenticated, public;
revoke all on table public.page_text from anon, authenticated, public;

grant select, insert, update, delete on table public.notebooks to authenticated, service_role;
grant select, insert, update, delete on table public.pages to authenticated, service_role;
grant select, insert, update, delete on table public.strokes to authenticated, service_role;
grant select, insert, update, delete on table public.page_text to authenticated, service_role;

drop index if exists public.pages_notebook_id_idx;
drop index if exists public.strokes_page_id_idx;

create index if not exists pages_notebook_user_idx
  on public.pages (notebook_id, user_id);

create index if not exists strokes_page_user_idx
  on public.strokes (page_id, user_id);

create index if not exists page_text_page_user_idx
  on public.page_text (page_id, user_id);
