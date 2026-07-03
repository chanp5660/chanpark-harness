# tests/fixtures — Test Fixture Catalog

## plans-mixed-markers.md
A synthetic Plans.md containing both v2 5-column table rows and checklist lines.
Expected table row counts: todo=2, TODO=2 (case variants), wip=2, WIP=2, done=2, Done=2, blocked=1 (7 rows total).
Also includes one prose sentence with "cc:wip" to verify counters ignore free-form text.

## mock-plugin-root/.claude-plugin/plugin.json
Minimal plugin.json with `name: "chanpark-harness"` and `version: "0.0.0-fixture"`.
Used by check-regression-guard.sh and future identity-check tests that need a clean fixture
rather than the live .claude-plugin/ directory.
