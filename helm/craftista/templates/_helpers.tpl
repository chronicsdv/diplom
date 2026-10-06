{{/* Полный образ сервиса repository:tag (тег по умолчанию = global.imageTag) */}}
{{- define "craftista.image" -}}
{{- $tag := default .root.Values.global.imageTag .svc.image.tag -}}
{{- printf "%s:%s" .svc.image.repository $tag -}}
{{- end -}}

{{/* Общие метки ресурса. Вызов: include "craftista.labels" (dict "root" . "name" "frontend") */}}
{{- define "craftista.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/part-of: craftista
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Метки для селекторов (неизменяемые) */}}
{{- define "craftista.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/* Имя секрета с реквизитами БД */}}
{{- define "craftista.dbSecretName" -}}
{{- .Values.database.existingSecret | default "craftista-db" -}}
{{- end -}}
