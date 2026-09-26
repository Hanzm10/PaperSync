# PaperSync

PaperSync keeps a digital copy of handwriting from the tablet. The cloud database is the Supabase project [PaperSync](https://supabase.com/dashboard/project/adsemxgqqzefhnqsdbbx/editor).

Signed-in users can read and write only their own rows. Writing without an account stays on the phone.

| Table | What it stores |
| --- | --- |
| `notebooks` | Notebook name and default ink color |
| `pages` | Sheets in a notebook, ordered by `page_index`, plus the paper rectangle |
| `strokes` | Pen strokes. `points` is a JSON array of `{x, y, p, t}` |
| `page_text` | Recognized handwriting for search on another device |

Migrations are in `supabase/migrations/`. Copy `.env.example` when connecting the app. The service role key stays on the server. 
