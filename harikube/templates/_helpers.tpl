{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "harikube.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "harikube.labels" -}}
app: harikube
helm.sh/chart: {{ include "harikube.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Generates a single shared TLS certificate context and caches it in .Values.
This guarantees that Secret and Webhook Configuration use the EXACT SAME CA instance 
on first install before the secret exists in the API server.
*/}}
{{/*
Generates/retrieves a cached TLS certificate context keyed by secretName.
Guarantees that Secret and Webhook Configuration use the EXACT SAME CA instance 
per secret on first install before the secret exists in the API server.
*/}}
{{- define "harikube.getOrGenTls" -}}
{{- $root := .root -}}
{{- $secretName := .secretName -}}
{{- $cn := .cn -}}
{{- $ns := $root.Release.Namespace -}}

{{/* Initialize the root tlsCache map if it doesn't exist yet */}}
{{- if not $root.Values.tlsCache -}}
  {{- $_ := set $root.Values "tlsCache" (dict) -}}
{{- end -}}

{{/* Check if this specific secretName has already been cached during this render run */}}
{{- if not (hasKey $root.Values.tlsCache $secretName) -}}
  {{- $existingSecret := lookup "v1" "Secret" $ns $secretName -}}
  {{- $caCert := "" -}}
  {{- $tlsCert := "" -}}
  {{- $tlsKey := "" -}}

  {{- if $existingSecret -}}
    {{/* Secret exists on cluster (upgrade run) */}}
    {{- $caCert = index $existingSecret.data "ca.crt" -}}
    {{- $tlsCert = index $existingSecret.data "tls.crt" -}}
    {{- $tlsKey = index $existingSecret.data "tls.key" -}}
  {{- else -}}
    {{/* First install: generate once and store in memory */}}
    {{- $ca := genCA (printf "%s-ca" $cn) 3650 -}}
    {{- $altNames := list $cn (printf "%s.%s" $cn $ns) (printf "%s.%s.svc" $cn $ns) (printf "%s.%s.svc.cluster.local" $cn $ns) -}}
    {{- $cert := genSignedCert $cn nil $altNames 3650 $ca -}}
    {{- $caCert = $ca.Cert | b64enc -}}
    {{- $tlsCert = $cert.Cert | b64enc -}}
    {{- $tlsKey = $cert.Key | b64enc -}}
  {{- end -}}

  {{/* Store in tlsCache map keyed by secretName */}}
  {{- $_ := set $root.Values.tlsCache $secretName (dict "caCert" $caCert "tlsCert" $tlsCert "tlsKey" $tlsKey) -}}
{{- end -}}

{{/* Return cached dict for this specific secretName */}}
{{- (index $root.Values.tlsCache $secretName) | toYaml -}}
{{- end -}}