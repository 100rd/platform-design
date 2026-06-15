{{/*
ADR-0028 platform taxonomy labels (dotted form) for the bare-metal policy bundle.
Applied to every CR so the SOC2 evidence is attributable on the Grafana $system axis.
*/}}
{{- define "baremetal-org-policy.labels" -}}
platform.system: {{ .Values.platform.system | quote }}
platform.component: {{ .Values.platform.component | quote }}
platform.owner: {{ .Values.platform.owner | quote }}
platform.env: {{ .Values.platform.env | quote }}
platform.managed-by: {{ .Values.platform.managedBy | quote }}
app.kubernetes.io/name: baremetal-org-policy
app.kubernetes.io/component: policy-bundle
{{- end -}}

{{/*
Common annotations carrying ADR provenance + DC attribution + enforcement mode.
*/}}
{{- define "baremetal-org-policy.annotations" -}}
adr: "ADR-0028,ADR-0040,ADR-0049,ADR-0050"
platform-design.io/dc: {{ .Values.dc | quote }}
platform-design.io/cluster: {{ .Values.clusterName | quote }}
platform-design.io/enforcement-mode: {{ .Values.enforcementMode | quote }}
{{- end -}}
