# Engineering challenges — platform interview loop

Three design challenges built on **this repository as it actually is**: its diagrams, ADRs,
specs and as-built divergences. They are not trivia. A candidate who has never touched
Cilium, Kargo or Pyrra can still do very well; a candidate who can recite every flag but cannot
reason about evidence, failure and composition will not.

| # | Challenge | Core question | Candidate brief | Interviewer guide |
|---|-----------|---------------|-----------------|-------------------|
| 1 | **The Ten Ephemeral Apps** | How do you make error-handling a *checkable contract* instead of a style guide? | [candidate/01-failure-contract.md](candidate/01-failure-contract.md) | [interviewer/01-failure-contract.md](interviewer/01-failure-contract.md) |
| 2 | **Prove It's the Cluster We Declared** | What does "100% sure a cluster meets requirements" mean, and what evidence would carry it? | [candidate/02-provable-clusters.md](candidate/02-provable-clusters.md) | [interviewer/02-provable-clusters.md](interviewer/02-provable-clusters.md) |
| 3 | **Ninety-Nine Percent of What?** | How do you know a platform of 150 services and shared data stores is 99% working? | [candidate/03-ninety-nine-percent.md](candidate/03-ninety-nine-percent.md) | [interviewer/03-ninety-nine-percent.md](interviewer/03-ninety-nine-percent.md) |

## What we are evaluating

Logic over technology knowledge. Each challenge is scored on the same five dimensions
(1 = absent, 4 = strong). Rubric details and anchors live in each interviewer guide.

| Dimension | The question behind it |
|-----------|------------------------|
| **Framing** | Did they challenge the ask, define terms, and find the real problem before solving? |
| **Mechanism** | Can they explain *how* a failure propagates or a guarantee holds, step by step? |
| **Verifiability** | For every claim, can they say what evidence would prove it — and how that evidence could lie? |
| **Trade-offs** | Do they name what their design costs, who pays, and when they would choose differently? |
| **Altitude** | Do they move between one pod and 150 services, one cluster and the fleet, without losing the thread? |

A strong hire scores 3+ on Framing, Mechanism and Verifiability. Trade-offs and Altitude
separate senior from staff.

## How to run a session

- **Format:** one challenge per 60-minute slot; or one challenge as a take-home (candidate
  brief only) followed by a 60-minute defence where you play the curveballs.
- **Before:** send the candidate brief and the repo pointers it lists. Do **not** send the
  interviewer guide — it contains the curveballs and the traps.
- **0–10 min:** candidate restates the problem and their framing. Interrupt only to ask
  "what do you mean by …?".
- **10–35 min:** candidate presents a design. Ask "how would you know?" after every claim.
- **35–55 min:** play curveballs one at a time, in the order given; stop when the signal is clear.
  Each curveball is written to invalidate a typical first design — the point is to watch how
  they *revise*, not whether they predicted it.
- **55–60 min:** "What in this repo would you change first, and what would you *not* touch?"

## Ground rules to tell the candidate

1. Any technology may be replaced. Saying "I would remove X" is a valid answer if argued.
2. "I don't know that tool" is fine; "I'd assume it works" is not.
3. Numbers matter. Back-of-envelope arithmetic is expected and encouraged.
4. There is no single correct answer. There are wrong ones: designs whose success cannot be
   observed, and guarantees that rest on a component that shares fate with the thing it guards.

## Repository pointers (shared by all challenges)

- System diagram: [`docs/architecture/platform-design.excalidraw`](../architecture/platform-design.excalidraw)
  (open in excalidraw.com; see [`DIAGRAMS.md`](../architecture/DIAGRAMS.md))
- Platform and developer contracts: [`engineering-manifest.md`](../engineering-manifest.md),
  [`developer-manifest.md`](../developer-manifest.md)
- Specs: [`specs/SPEC-INDEX.md`](../../specs/SPEC-INDEX.md)
- Decisions: [`docs/adrs/`](../adrs/)
