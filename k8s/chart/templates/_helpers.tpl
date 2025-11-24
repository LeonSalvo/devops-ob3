{{- define "backend.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "backend.fullname" -}}
{{- printf "%s" (include "backend.name" .) -}}
{{- end -}}

{{- define "backend.labels" -}}
app.kubernetes.io/name: {{ include "backend.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end -}}
