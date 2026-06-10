{{/*
ml-monitoring Helm helpers — ADR-0038
All platform labels are inlined in each template file rather than via a
shared helper, to avoid Helm whitespace trimming edge-cases with nindent.
This file is retained for selector and name helpers.
*/}}

{{/*
Chart name helper
*/}}
{{- define "ml-monitoring.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
Usage: {{- include "ml-monitoring.selectorLabels" (dict "name" "ml-drift-exporter") | nindent 6 }}
*/}}
{{- define "ml-monitoring.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
{{- end }}
