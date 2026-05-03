# Triage Labels

The vibe-* skills speak in terms of two label families — **state** roles (one per issue, describing where the issue is in the workflow) and **category** roles (one per issue, describing what kind of work it is). This file maps both families to the actual label strings used in this repo's issue tracker.

## State labels

| Canonical role    | Label in our tracker | Meaning                                  |
| ----------------- | -------------------- | ---------------------------------------- |
| `needs-triage`    | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`      | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human` | `ready-for-human`    | Requires human implementation            |
| `wontfix`         | `wontfix`            | Will not be actioned                     |

## Category labels

| Canonical role | Label in our tracker | Meaning                          |
| -------------- | -------------------- | -------------------------------- |
| `bug`          | `bug`                | Something is broken              |
| `enhancement`  | `enhancement`        | New feature or improvement       |

(GitHub ships `bug` and `enhancement` as default labels in every new repo, so the defaults usually work. Override the right-hand column if your repo uses different names.)

When a skill mentions a role (e.g. "apply the AFK-ready triage label" or "tag with the bug category label"), use the corresponding label string from these tables.

Edit the right-hand column to match whatever vocabulary you actually use.
