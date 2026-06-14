# Architecture diagrams (Excalidraw)

Editable `.excalidraw` sources (the JSON is the source of truth). View / edit any of them by:

- **excalidraw.com** — drag-and-drop the file onto the canvas, or ☰ menu → **Open**.
- **VS Code** — the *Excalidraw* extension renders `.excalidraw` files inline.

> GitHub shows these as raw JSON, not images — open them with one of the tools above.

| Diagram | File | Scope |
|---------|------|-------|
| **platform-design — system architecture** | [`platform-design.excalidraw`](platform-design.excalidraw) | Whole estate, layered: product (transaction-analytics) · Delivery (GitOps/CI-CD) · AWS Landing Zone · Network · EKS + GPU cluster · Observability & FinOps · Data plane · GCP ML slice · UK edge. Includes a "Layer reference" with one description card per layer. |
| **GCP ML Platform — with descriptions** | [`../gcp-ml-platform/architecture-v2.excalidraw`](../gcp-ml-platform/architecture-v2.excalidraw) | The WS-A…F build (ADR-0036–0041): pipeline ①→⑥, drift→retrain loop, GKE foundation, security panel, golden paths — plus a per-component / per-step reference card per workstream. |
| **GCP ML Platform — compact** | [`../gcp-ml-platform/architecture.excalidraw`](../gcp-ml-platform/architecture.excalidraw) | The same WS-A…F flow without the description cards. |

**Style:** classic sans-serif font, clean (non-sketch) lines, one colour per area.

The GCP ML Platform diagrams accompany [`../gcp-ml-platform/IMPLEMENTATION_PLAN.md`](../gcp-ml-platform/IMPLEMENTATION_PLAN.md); the platform-design landscape sits alongside the other docs in this directory.
