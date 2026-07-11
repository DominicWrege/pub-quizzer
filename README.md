# Pub Quizzer

Echtzeit-Pub-Quiz für Teams. Phoenix LiveView + SQLite.

## Setup

```bash
# Nix shell automatisch laden (einmalig):
direnv allow

# Abhängigkeiten installieren + Datenbank anlegen:
mix setup

# Dev server starten:
mix phx.server
```

Dann http://localhost:4000 im Browser öffnen.

## Admin

- Login unter http://localhost:4000/admin/login
- Kennwort (dev): `changeme` (via `ADMIN_PASSWORD` env var überschreibbar)

## Quiz abspielen

1. Admin: Event erstellen unter `/admin/events`
2. Admin: Themen + Fragen verwalten unter `/admin/topics`
3. Teams: Beitritt über Startseite mit 4-stelligem Code
4. Admin: "Quiz starten" in der Event-Ansicht
5. Moderator-Konsole leitet das Quiz, Teams sehen Fragen + Antwortoptionen
