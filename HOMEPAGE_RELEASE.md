# Alem homepage — 25 November 2026

Connects the Finance product to the longer-term control layer for agent payments.
The hero includes a local, clearly labelled policy illustration: approved recipient
under AED 20,000 passes; over-limit requests require approval; unknown recipients
are blocked. Its bounded decision log is browser-local and resets on reload.
No payment requests, tracking or customer data are sent by this demo.

Adds the invoice-to-control thesis, one Live / Private beta / Next via partners
roadmap, founder profile, separate demo / partnership / investor email links,
Telegram contact and a 1200 × 630 Open Graph card. No fabricated product screenshot,
calendar link, client metrics or team members are included. Founder and Antler
logos are retained; the Antler vector was sourced from https://www.antler.co/.

## Deploy

Use the full reviewed commit SHA with `deploy-home.sh --check SHA` or
`deploy-home.sh --apply SHA` on the existing server, with sudo.

Only `index.html`, `llms.txt` and `alem-social-v3.png` are deployed to the existing
homepage root. The script backs up existing files, verifies public responses and
restores the previous release on failure. Finance, Gateway, DNS, databases and
Caddy configuration are unchanged; no restart is needed.

## Final copy alignment

The global headline is “Infrastructure for agentic commerce. Starting with
finance.” Primary demo actions consistently read “Book a demo”. Added the
control-context explanation and a dedicated Gateway beta section. Future
execution via licensed partners remains explicitly planned. No customer
screenshot or fabricated live transaction is presented.

## Validation

Browser checks passed for all three policy outcomes and their decision log,
mobile menu and FAQ. Final copy/layout checked at desktop and 375px content
width, with no horizontal overflow. HTML nesting, unique IDs, anchor targets,
structured metadata, JavaScript and shell syntax checks passed. An isolated
deploy fixture verified no-write check mode, three-file deployment and complete
rollback when public social-image verification fails. No live deployment has
been performed by this workspace.
