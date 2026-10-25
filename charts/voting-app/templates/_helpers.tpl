{{- define "voting-app.labels" -}}
app.kubernetes.io/part-of: voting-app
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "voting-app.image" -}}
{{ .root.Values.image.registry }}/{{ .name }}:{{ .tag | default .root.Values.image.tag }}
{{- end }}