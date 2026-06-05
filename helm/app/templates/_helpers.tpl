---
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}

{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := include "app.name" . -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "app.labels" -}}
helm.sh/chart: {{ include "app.chart" . }}
{{ include "app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "app.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Shared pod spec — rendered as the body of `template.spec:` for BOTH the
Deployment and the Argo Rollouts Rollout so the container/pod definition never
diverges between the two workload kinds. Include with `nindent 6`.
*/}}
{{- define "app.podSpec" -}}
serviceAccountName: {{ include "app.serviceAccountName" . }}
terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds | default 30 }}
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.initContainers }}
initContainers:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
  - name: {{ .Chart.Name }}
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{- with .Values.containerSecurityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    ports:
      - name: http
        containerPort: {{ .Values.containerPort }}
        protocol: TCP
    {{- with .Values.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if .Values.probes.liveness.enabled }}
    livenessProbe:
      httpGet:
        path: {{ .Values.probes.liveness.httpGet.path }}
        port: {{ .Values.probes.liveness.httpGet.port }}
      initialDelaySeconds: {{ .Values.probes.liveness.initialDelaySeconds }}
      periodSeconds: {{ .Values.probes.liveness.periodSeconds }}
      timeoutSeconds: {{ .Values.probes.liveness.timeoutSeconds }}
      failureThreshold: {{ .Values.probes.liveness.failureThreshold }}
    {{- end }}
    {{- if .Values.probes.readiness.enabled }}
    readinessProbe:
      httpGet:
        path: {{ .Values.probes.readiness.httpGet.path }}
        port: {{ .Values.probes.readiness.httpGet.port }}
      initialDelaySeconds: {{ .Values.probes.readiness.initialDelaySeconds }}
      periodSeconds: {{ .Values.probes.readiness.periodSeconds }}
      timeoutSeconds: {{ .Values.probes.readiness.timeoutSeconds }}
      failureThreshold: {{ .Values.probes.readiness.failureThreshold }}
    {{- end }}
    {{- if .Values.probes.startup.enabled }}
    startupProbe:
      httpGet:
        path: {{ .Values.probes.startup.httpGet.path }}
        port: {{ .Values.probes.startup.httpGet.port }}
      initialDelaySeconds: {{ .Values.probes.startup.initialDelaySeconds }}
      periodSeconds: {{ .Values.probes.startup.periodSeconds }}
      timeoutSeconds: {{ .Values.probes.startup.timeoutSeconds }}
      failureThreshold: {{ .Values.probes.startup.failureThreshold }}
    {{- end }}
    {{- with .Values.lifecycle }}
    lifecycle:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if or .Values.externalSecrets.enabled .Values.envFrom }}
    envFrom:
      {{- if .Values.externalSecrets.enabled }}
      - secretRef:
          name: {{ include "app.fullname" . }}-secrets
      {{- end }}
      {{- with .Values.envFrom }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- end }}
    {{- with .Values.env }}
    env:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- with .Values.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- range . }}
  - maxSkew: {{ .maxSkew }}
    topologyKey: {{ .topologyKey }}
    whenUnsatisfiable: {{ .whenUnsatisfiable }}
    labelSelector:
      matchLabels:
        {{- include "app.selectorLabels" $ | nindent 8 }}
  {{- end }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Pod template metadata (labels + annotations) shared by Deployment and Rollout.
Include with `nindent 6` under `template:`.
*/}}
{{- define "app.podTemplateMeta" -}}
metadata:
  labels:
    {{- include "app.selectorLabels" . | nindent 4 }}
    {{- with .Values.labels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with .Values.podAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
