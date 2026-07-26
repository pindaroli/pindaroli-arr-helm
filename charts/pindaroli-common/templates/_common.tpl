{{/*
Generic deployment template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr", "lidarr", "readarr", "bazarr", "qbittorrent", "prowlarr", "jellyseerr")
*/}}
{{- define "pindaroli-common.deployment" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $compValues := index $root.Values $component -}}
{{- $persistence := $compValues.persistence | default dict -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $root.Release.Name }}-{{ $component }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
spec:
  {{- if not $compValues.autoscaling.enabled }}
  replicas: {{ $compValues.replicaCount }}
  {{- end }}
  strategy:
    {{- $compValues.deployment.strategy | toYaml | nindent 4 }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ $component }}
      app.kubernetes.io/instance: {{ $root.Release.Name }}
  template:
    metadata:
      {{- with $compValues.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        app.kubernetes.io/name: {{ $component }}
        app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
        app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
        app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
    spec:
      {{- with $compValues.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ $compValues.serviceAccount.name | default (printf "%s-%s" $root.Release.Name $component) }}
      securityContext:
        {{- toYaml $compValues.podSecurityContext | nindent 8 }}
      {{- if or (and $root.Values.jellyfin.persistence.media.enabled $persistence.enabled $persistence.createInitContainer) $compValues.initContainers }}
      initContainers:
        {{- if and $root.Values.jellyfin.persistence.media.enabled $persistence.enabled $persistence.createInitContainer }}
        - name: init-directories
          image: busybox
          command: ['sh', '-c', 'mkdir -p /media/{{ $persistence.path }} /media/{{ $root.Values.qbittorrent.persistence.path }} && chown -R 1000:1000 /media/{{ $persistence.path }} /media/{{ $root.Values.qbittorrent.persistence.path }}']
          volumeMounts:
            - name: media
              mountPath: /media
        {{- end }}
        {{- if $compValues.initContainers }}
          {{- toYaml $compValues.initContainers | nindent 8 }}
        {{- end }}
      {{- end }}
      volumes:
        - name: config
          {{- if $persistence.enabled }}
          persistentVolumeClaim:
            claimName: {{ $persistence.existingClaim | default (printf "%s-%s" $root.Release.Name $component) }}
          {{- else }}
          emptyDir: { }
          {{- end }}
        - name: media
          {{- if and $root.Values.jellyfin.persistence.media.enabled $persistence.enabled }}
          persistentVolumeClaim:
            claimName: {{ $root.Values.jellyfin.persistence.media.existingClaim | default (printf "%s-jellyfin-media" $root.Release.Name) }}
          {{- else }}
          emptyDir: { }
          {{- end }}
        {{- if $persistence.additionalVolumes }}
          {{- $persistence.additionalVolumes | toYaml | nindent 8 }}
        {{- end }}
      containers:
        - name: {{ $component }}
          securityContext:
            {{- toYaml $compValues.securityContext | nindent 12 }}
          image: "{{ $compValues.image.repository }}:{{ $compValues.image.tag | default $root.Chart.AppVersion }}"
          imagePullPolicy: {{ $compValues.image.pullPolicy }}
          volumeMounts:
            - mountPath: {{ $persistence.configPath | default (eq $component "jellyseerr" | ternary "/app/config" "/config") }}
              name: config
          {{- if and $root.Values.jellyfin.persistence.media.enabled $persistence.enabled }}
            - mountPath: /media
              name: media
          {{- end }}
          {{- if $persistence.additionalMounts }}
            {{- $persistence.additionalMounts | toYaml | nindent 12 }}
          {{- end }}
          ports:
            - name: http
              containerPort: {{ $compValues.service.port }}
              protocol: TCP
          env:
            {{- range $k,$v := $compValues.env }}
            - name: {{ $k }}
              {{- if or (kindIs "map" $v) (typeIs "map[string]interface {}" $v) }}
              {{- toYaml $v | nindent 14 }}
              {{- else }}
              value: {{ $v | quote }}
              {{- end }}
            {{- end }}
          {{- with $compValues.envFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- $livenessPath := "/ping" }}
          {{- $livenessFailureThreshold := 12 }}
          {{- $livenessPeriodSeconds := 10 }}
          {{- if $compValues.livenessProbe }}
            {{- $livenessPath = $compValues.livenessProbe.path | default $livenessPath }}
            {{- $livenessFailureThreshold = $compValues.livenessProbe.failureThreshold | default $livenessFailureThreshold }}
            {{- $livenessPeriodSeconds = $compValues.livenessProbe.periodSeconds | default $livenessPeriodSeconds }}
          {{- end }}
          {{- $startupPath := "/ping" }}
          {{- $startupFailureThreshold := 30 }}
          {{- $startupPeriodSeconds := 10 }}
          {{- if $compValues.startupProbe }}
            {{- $startupPath = $compValues.startupProbe.path | default $startupPath }}
            {{- $startupFailureThreshold = $compValues.startupProbe.failureThreshold | default $startupFailureThreshold }}
            {{- $startupPeriodSeconds = $compValues.startupProbe.periodSeconds | default $startupPeriodSeconds }}
          {{- end }}
          livenessProbe:
            httpGet:
              path: {{ $livenessPath }}
              port: http
            failureThreshold: {{ $livenessFailureThreshold }}
            periodSeconds: {{ $livenessPeriodSeconds }}
          startupProbe:
            httpGet:
              path: {{ $startupPath }}
              port: http
            failureThreshold: {{ $startupFailureThreshold }}
            periodSeconds: {{ $startupPeriodSeconds }}
          resources:
            {{- toYaml $compValues.resources | nindent 12 }}
      {{- with $compValues.extraContainers }}
      {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $compValues.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $compValues.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $compValues.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end -}}

{{/*
Generic service template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr")
- "defaultPort": the default port if not defined in values
*/}}
{{- define "pindaroli-common.service" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $defaultPort := .defaultPort -}}
{{- $compValues := index $root.Values $component -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ $root.Release.Name }}-{{ $component }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
spec:
  type: {{ $compValues.service.type | default "ClusterIP" }}
  ports:
    - port: {{ $compValues.service.port | default $defaultPort }}
      targetPort: http
      protocol: TCP
      name: http
{{- if (and (eq $compValues.service.type "NodePort") (not (empty $compValues.service.nodePort))) }}
      nodePort: {{ $compValues.service.nodePort }}
{{- end }}
{{- if and $compValues.monitoring $compValues.monitoring.enabled }}
    - port: {{ $compValues.monitoring.port | default 9707 }}
      targetPort: metrics
      protocol: TCP
      name: metrics
{{- end }}
  selector:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name }}
{{- end -}}

{{/*
Generic ServiceAccount template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr")
*/}}
{{- define "pindaroli-common.serviceAccount" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $compValues := index $root.Values $component -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $root.Release.Name }}-{{ $component }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
  {{- with $compValues.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}

{{/*
Generic PVC template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr")
*/}}
{{- define "pindaroli-common.pvc" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $compValues := index $root.Values $component -}}
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: {{ $root.Release.Name }}-{{ $component }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
  {{- if $compValues.persistence.annotations }}
  annotations:
    {{- toYaml $compValues.persistence.annotations | nindent 4 }}
  {{- end }}
spec:
  accessModes:
    - {{ $compValues.persistence.accessMode | quote }}
  {{- if $compValues.persistence.storageClass }}
  storageClassName: {{ $compValues.persistence.storageClass | quote }}
  {{- end }}
  resources:
    requests:
      storage: {{ $compValues.persistence.size | quote }}
{{- end -}}

{{/*
Generic Ingress template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr")
*/}}
{{- define "pindaroli-common.ingress" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $compValues := index $root.Values $component -}}
{{- $fullName := printf "%s-%s" $root.Release.Name $component -}}
{{- $svcPort := $compValues.service.port -}}
{{- if and $compValues.ingress.className (not (semverCompare ">=1.18-0" $root.Capabilities.KubeVersion.GitVersion)) }}
  {{- if not (hasKey $compValues.ingress.annotations "kubernetes.io/ingress.class") }}
  {{- $_ := set $compValues.ingress.annotations "kubernetes.io/ingress.class" $compValues.ingress.className}}
  {{- end }}
{{- end }}
{{- if semverCompare ">=1.19-0" $root.Capabilities.KubeVersion.GitVersion -}}
apiVersion: networking.k8s.io/v1
{{- else if semverCompare ">=1.14-0" $root.Capabilities.KubeVersion.GitVersion -}}
apiVersion: networking.k8s.io/v1beta1
{{- else -}}
apiVersion: extensions/v1beta1
{{- end }}
kind: Ingress
metadata:
  name: {{ $fullName }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
  {{- with $compValues.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if and $compValues.ingress.className (semverCompare ">=1.18-0" $root.Capabilities.KubeVersion.GitVersion) }}
  ingressClassName: {{ $compValues.ingress.className }}
  {{- end }}
  {{- if $compValues.ingress.tls }}
  tls:
    {{- range $compValues.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range $compValues.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            {{- if and .pathType (semverCompare ">=1.18-0" $root.Capabilities.KubeVersion.GitVersion) }}
            pathType: {{ .pathType }}
            {{- end }}
            backend:
              {{- if semverCompare ">=1.19-0" $root.Capabilities.KubeVersion.GitVersion }}
              service:
                name: {{ $fullName }}
                port:
                  number: {{ $svcPort }}
              {{- else }}
              serviceName: {{ $fullName }}
              servicePort: {{ $svcPort }}
              {{- end }}
          {{- end }}
    {{- end }}
{{- end -}}

{{/*
Generic HPA template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr")
*/}}
{{- define "pindaroli-common.hpa" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $compValues := index $root.Values $component -}}
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $root.Release.Name }}-{{ $component }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ $root.Release.Name }}-{{ $component }}
  minReplicas: {{ $compValues.autoscaling.minReplicas }}
  maxReplicas: {{ $compValues.autoscaling.maxReplicas }}
  metrics:
    {{- if $compValues.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        targetAverageUtilization: {{ $compValues.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if $compValues.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        targetAverageUtilization: {{ $compValues.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end -}}

{{/*
Generic ServiceAccount template for Servarr stack components.
Pass a dictionary with:
- "root": the root context (.)
- "component": the name of the component (e.g. "sonarr", "radarr")
*/}}
{{- define "pindaroli-common.serviceaccount" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $compValues := index $root.Values $component -}}
{{- if $compValues.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $compValues.serviceAccount.name | default (printf "%s-%s" $root.Release.Name $component) }}
  labels:
    app.kubernetes.io/name: {{ $component }}
    app.kubernetes.io/instance: {{ $root.Release.Name | quote }}
    app.kubernetes.io/version: {{ $root.Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ $root.Release.Service | quote }}
  {{- with $compValues.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end -}}
