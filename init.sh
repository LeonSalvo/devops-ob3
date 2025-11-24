#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="${ROOT_DIR}/reports"

IMAGE="${IMAGE:-registry.konoba.space/viajes:v1}"

RELEASE_NAME="${RELEASE_NAME:-backend}"
CHART_DIR="${CHART_DIR:-k8s/chart}"

K8S_MANIFEST_DIR="${K8S_MANIFEST_DIR:-k8s}"
KYVERNO_POLICY_DIR="${KYVERNO_POLICY_DIR:-k8s/policies}"
NONCOMPLIANT_MANIFEST="${NONCOMPLIANT_MANIFEST:-k8s/policies/non-compliant-pod.yaml}"

DEVOPS_NS="devops-ucu"
NAMESPACE_KYVERNO="kyverno"

PORT_FORWARD_PID=""

log()  { printf '\n[INFO] %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
err()  { printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }

check_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "No se encontró el comando '$cmd'"
    return 1
  fi
  return 0
}

init() {
  mkdir -p "$REPORTS_DIR"

  log "Chequeando comandos obligatorios..."
  local required=(node npm docker kubectl helm kube-linter)
  for c in "${required[@]}"; do
    check_cmd "$c" || err "Falta comando obligatorio: $c"
  done

  log "Chequeando comandos opcionales..."
  for c in trivy curl; do
    check_cmd "$c" || true
  done

  IMAGE_REPO="${IMAGE%:*}"
  IMAGE_TAG="${IMAGE##*:}"
}

step_npm_audit() {
  log "Instalando dependencias npm..."
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi

  log "Ejecutando npm audit -> reports/npm-audit.txt"
  npm audit > "${REPORTS_DIR}/npm-audit.txt" || true
}

step_lint() {
  if [ -f "${ROOT_DIR}/.eslintrc.js" ] || [ -f "${ROOT_DIR}/.eslintrc.cjs" ] || [ -f "${ROOT_DIR}/.eslintrc.json" ]; then
    log "Ejecutando ESLint sobre src/..."
    npx eslint "src/**/*.{js,jsx,ts,tsx}" || true
  else
    warn "No se encontró config de ESLint, saltando."
  fi
}

step_pull_image() {
  log "Usando imagen: ${IMAGE}"
  if ! docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    log "Imagen no encontrada localmente, haciendo docker pull..."
    docker pull "${IMAGE}"
  else
    log "Imagen ya existe localmente, no se hace pull."
  fi
}

step_trivy() {
  if ! check_cmd trivy >/dev/null 2>&1; then
    warn "Trivy no está instalado, saltando escaneo de imagen."
    return
  fi

  log "Escaneando imagen con Trivy (contenedor) -> ${REPORTS_DIR}/trivy-report.txt"
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest \
    image --format table "${IMAGE}" \
    > "${REPORTS_DIR}/trivy-report.txt" || true
}

step_image_analysis() {
  log "Analizando tamaño y capas de la imagen..."

  local size_bytes
  size_bytes="$(docker image inspect "${IMAGE}" --format='{{.Size}}')"
  local size_mb
  size_mb=$(awk -v s="$size_bytes" 'BEGIN { printf "%.2f", s/1024/1024 }')

  local layer_count
  layer_count="$(docker history "${IMAGE}" --no-trunc | tail -n +2 | wc -l | tr -d ' ')"

  {
    echo "# Image analysis"
    echo
    echo "- Image: ${IMAGE}"
    echo "- Total size (MB): ${size_mb}"
    echo "- Layer count: ${layer_count}"
    echo
  } > "${REPORTS_DIR}/image-analysis.md"

  log "Guardado reports/image-analysis.md"
}

step_helm_deploy() {
  log "Desplegando aplicación vía Helm chart (${CHART_DIR}) en namespace ${DEVOPS_NS}..."
  if [ ! -d "${CHART_DIR}" ]; then
    err "No existe el directorio del chart: ${CHART_DIR}"
  fi

  helm upgrade --install "${RELEASE_NAME}" "${CHART_DIR}" \
    --namespace "${DEVOPS_NS}" --create-namespace \
    --set image.repository="${IMAGE_REPO}" \
    --set image.tag="${IMAGE_TAG}" || err "Fallo el helm upgrade --install"

  log "Esperando a que el deployment se encuentre listo..."
  kubectl rollout status deployment/"${RELEASE_NAME}" -n "${DEVOPS_NS}" || warn "Timeout o error en rollout status"
}

step_port_forward() {
  local LOCAL_PORT="${LOCAL_PORT:-3000}"
  local SERVICE_PORT=80

  log "Haciendo port-forward svc/backend-svc:${SERVICE_PORT} -> localhost:${LOCAL_PORT} (namespace ${DEVOPS_NS})..."

  kubectl port-forward svc/backend-svc "${LOCAL_PORT}:${SERVICE_PORT}" -n "${DEVOPS_NS}" >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!

  sleep 2
  if ! kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
    warn "Port-forward falló. Verificá que el Service backend-svc exista y exponga el puerto ${SERVICE_PORT}."
    PORT_FORWARD_PID=""
  else
    log "Port-forward activo. Podés usar http://localhost:${LOCAL_PORT} (redirige al containerPort 3000)."
  fi
}

step_install_kyverno() {
  log "Instalando Kyverno en el namespace '${NAMESPACE_KYVERNO}'..."

  if ! kubectl get ns "${NAMESPACE_KYVERNO}" >/dev/null 2>&1; then
    kubectl create namespace "${NAMESPACE_KYVERNO}"
  fi

  helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  helm upgrade --install kyverno kyverno/kyverno \
    -n "${NAMESPACE_KYVERNO}" --create-namespace >/dev/null 2>&1 || true

  log "Esperando a que el CRD clusterpolicies.kyverno.io esté disponible..."
  for i in {1..30}; do
    if kubectl get crd clusterpolicies.kyverno.io >/dev/null 2>&1; then
      log "CRD clusterpolicies.kyverno.io listo."
      return 0
    fi
    sleep 2
  done

  warn "No se pudo confirmar el CRD clusterpolicies.kyverno.io tras varios intentos."
}

step_kyverno() {
  local policy_dir="${KYVERNO_POLICY_DIR}"

  if [ ! -d "${policy_dir}" ]; then
    warn "No existe ${policy_dir}, no aplico políticas Kyverno."
    return
  fi

  log "Aplicando políticas Kyverno desde ${policy_dir}..."
  if ! kubectl apply -f "${policy_dir}" > /dev/null 2>&1; then
    warn "Error aplicando policies de Kyverno (ver salida de kubectl apply si es necesario)."
  fi

  if ! kubectl get ns "${DEVOPS_NS}" >/dev/null 2>&1; then
    log "Creando namespace '${DEVOPS_NS}' para probar el pod no conforme..."
    kubectl create namespace "${DEVOPS_NS}" >/dev/null 2>&1 || true
  fi

  if [ -f "${NONCOMPLIANT_MANIFEST}" ]; then
    log "Probando manifiesto NO conforme (${NONCOMPLIANT_MANIFEST})..."
    kubectl delete -f "${NONCOMPLIANT_MANIFEST}" >/dev/null 2>&1 || true

    set +e
    kubectl apply -f "${NONCOMPLIANT_MANIFEST}" \
      > "${REPORTS_DIR}/kyverno-noncompliant.log" 2>&1
    local rc=$?
    set -e

    if [ $rc -eq 0 ]; then
      warn "El manifiesto no conforme se aplicó sin error. Revisá las policies y el log reports/kyverno-noncompliant.log."
    else
      log "Kyverno bloqueó el manifiesto no conforme (ver reports/kyverno-noncompliant.log)."
    fi
  else
    warn "No existe ${NONCOMPLIANT_MANIFEST}."
  fi
}

step_kubelinter() {
  if [ ! -d "${K8S_MANIFEST_DIR}" ]; then
    warn "No existe directorio ${K8S_MANIFEST_DIR}, no se ejecuta kube-linter."
    return
  fi

  log "Ejecutando kube-linter sobre ${K8S_MANIFEST_DIR} -> reports/kubelinter.txt"
  if ! kube-linter lint "${K8S_MANIFEST_DIR}" > "${REPORTS_DIR}/kubelinter.txt" 2>&1; then
    warn "kube-linter encontró problemas (esto es esperado para el pod no conforme). Ver reports/kubelinter.txt"
  fi
}

cleanup() {
  log "Limpiando recursos creados por el script..."

  if [ -n "${PORT_FORWARD_PID}" ] && kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
    log "Deteniendo port-forward (PID ${PORT_FORWARD_PID})..."
    kill "${PORT_FORWARD_PID}" 2>/dev/null || true
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi

  set +e
  if helm status "${RELEASE_NAME}" -n "${DEVOPS_NS}" >/dev/null 2>&1; then
    log "Desinstalando release Helm ${RELEASE_NAME}..."
    helm uninstall "${RELEASE_NAME}" -n "${DEVOPS_NS}" >/dev/null 2>&1 || true
  fi

  if [ -f "${NONCOMPLIANT_MANIFEST}" ]; then
    kubectl delete -f "${NONCOMPLIANT_MANIFEST}" >/dev/null 2>&1 || true
  fi
  set -e

  log "Limpieza completada (release backend y pod no conforme eliminados si existían)."
}

main() {
  trap 'cleanup; exit 0' INT TERM

  init

  step_install_kyverno
  step_kyverno
  step_kubelinter

  step_npm_audit
  step_lint
  step_pull_image
  step_trivy
  step_image_analysis

  step_helm_deploy
  step_port_forward

  log "API desplegada en el cluster (namespace ${DEVOPS_NS}) y expuesta en localhost:${LOCAL_PORT:-3000}."
  printf '\n[INFO] Presioná ENTER cuando quieras apagar la API, cortar el port-forward y limpiar el cluster...\n'
  read -r _

  cleanup
  log "Script terminado."
}

main "$@"
