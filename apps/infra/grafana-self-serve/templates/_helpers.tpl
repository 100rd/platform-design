{{/*
grafana-self-serve helpers
ADR-0039: Self-Serve Observability
*/}}

{{/*
Validate required team fields. Called at the top of every template.
helm lint will surface the error if any required field is empty.
*/}}
{{- define "grafana-self-serve.validate" -}}
{{- $_ := required "team.name is required" .Values.team.name -}}
{{- $_ := required "team.slug is required" .Values.team.slug -}}
{{- $_ := required "team.namespace is required" .Values.team.namespace -}}
{{- $_ := required "team.system is required" .Values.team.system -}}
{{- $_ := required "team.owner is required" .Values.team.owner -}}
{{- $_ := required "team.env is required" .Values.team.env -}}
{{- end -}}

{{/*
Common ADR-0028 labels applied to every resource.
platform.system is always "observability" for the self-serve scaffolding itself.
*/}}
{{- define "grafana-self-serve.labels" -}}
platform.system: "observability"
platform.component: {{ .component | quote }}
platform.env: {{ .root.Values.team.env | quote }}
platform.owner: {{ .root.Values.team.slug | quote }}
platform.managed-by: "argocd"
app.kubernetes.io/name: "grafana-self-serve"
app.kubernetes.io/instance: {{ .root.Values.team.slug | quote }}
app.kubernetes.io/component: {{ .component | quote }}
app.kubernetes.io/managed-by: "Helm"
{{- end -}}

{{/*
Grafana dashboard ConfigMap labels — enables the Grafana sidecar to discover
and load the dashboard automatically.
*/}}
{{- define "grafana-self-serve.dashboardLabels" -}}
grafana_dashboard: "1"
platform.system: "observability"
platform.component: "dashboard"
platform.env: {{ .Values.team.env | quote }}
platform.owner: {{ .Values.team.slug | quote }}
platform.managed-by: "argocd"
{{- end -}}

{{/*
Uppercase team slug used as alert name prefix (prevents alertname collisions
across teams when aggregating in Alertmanager).
Example: team-checkout -> TEAM_CHECKOUT
*/}}
{{- define "grafana-self-serve.alertPrefix" -}}
{{- .Values.team.slug | upper | replace "-" "_" -}}
{{- end -}}

{{/*
Grafana folder UID — stable and deterministic from the team slug.
Grafana requires folder UIDs to be max 40 chars.
*/}}
{{- define "grafana-self-serve.folderUid" -}}
{{- printf "team-%s" .Values.team.slug | trunc 40 -}}
{{- end -}}
