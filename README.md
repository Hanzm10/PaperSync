# PaperSync

PaperSync keeps a digital copy of handwriting from the tablet. The phone app is a quiet notes tool: a library, live capture, a page editor, handwriting search, and pen pairing.

## Layout

- `app/` is the Flutter project.
- `docs/` records the v1 pen protocol and the decisions later phases build on.
- `docs/plans/` is the software build plan (start at [docs/plans/00-index.md](docs/plans/00-index.md)).
- `app/env/example.json` is the template for local defines. Other `app/env/*.json` files stay off the repo.

## Run

```bash
cd app
flutter pub get
flutter run
```
