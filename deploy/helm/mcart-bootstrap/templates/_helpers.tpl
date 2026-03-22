{{- define "mcart-bootstrap.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mcart-bootstrap.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "mcart-bootstrap.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
