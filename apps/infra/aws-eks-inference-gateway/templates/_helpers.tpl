{{/*
ADR-0028 platform taxonomy labels (Kubernetes-plane, dotted keys) for every object.
*/}}
{{- define "aws-eks-inference-gateway.labels" -}}
{{- range $k, $v := .Values.platformLabels }}
{{ $k }}: {{ $v | quote }}
{{- end }}
{{- end -}}
