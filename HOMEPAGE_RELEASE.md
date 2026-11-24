# Agentic commerce homepage — 24 November 2026

The homepage now presents one company story: infrastructure for agentic commerce,
starting with invoice approvals and payment matching. It retains the existing
Alem symbol, Finance product and workspace links, and private-beta Gateway link.

The founder confirmed $17,500 received for Finance AI Agent. The page labels
eight pilots as across Alem. The invoice example is illustrative. Payment
execution is explicitly planned, and Gateway controls remain a private beta.

## Scope

Only `index.html` and `llms.txt` are deployed. Finance, Gateway, password recovery,
databases, DNS and Caddy configuration are not modified. No restart is needed.

## Deployment on the existing server

Use the full reviewed commit SHA. Download `deploy-home.sh` from that commit,
then run `sudo bash deploy-home.sh --check COMMIT_SHA` followed by
`sudo bash deploy-home.sh --apply COMMIT_SHA`.

The script checks the known homepage root, validates downloaded content, backs
up both files, replaces them atomically, and compares public HTML and metadata
with the release. On failure it restores the previous files. The backup path is
printed on completion. `deploy-sites.sh` is the legacy combined-site deployment;
use `deploy-home.sh` for this release.

## Validation

Desktop and mobile browser review passed, including menu navigation, invoice
tabs and FAQ expansion. The mobile document has no horizontal overflow.
JavaScript syntax, shell syntax and Git whitespace checks passed.
An isolated deployment fixture verified check mode without writes, successful
replacement with backups, and restoration after public verification failure.
These fixture tests do not imply that production has been deployed.

## 25 November update

Removed the three public traction metrics at the founder’s request. Retained
Antler, angel investors and program alumni in one responsive strip. Removed
the obsolete traction footer note and updated deployment content validation.

Removed Antoine’s public profile at the founder’s request. The founder layout
now shows Dinara only. The backing strip uses the Antler vector logo sourced
from https://www.antler.co/ and omits the angel-investor label. SVG is embedded
in the homepage, so no additional assets or deployment paths are required.
