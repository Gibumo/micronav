#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# AVISO: no tenía acceso a tu render_and_upload.sh original --
# lo reconstruí a partir de lo que se alcanza a inferir del log
# de una corrida anterior (los mensajes "=== ... ===" y el
# patrón "upload: ..." de `aws s3 sync`). Revísalo con cuidado
# antes de confiar en él, sobre todo si el original tenía pasos
# adicionales que no aparecían en las 40 líneas de log que
# compartiste.
# ============================================================

: "${S3_BUCKET:?Falta S3_BUCKET en tu .env}"
AUTO_SHUTDOWN="${AUTO_SHUTDOWN:-false}"
RMD_FILE="comparison_samples_09092026.Rmd"
OUTPUT_DIR="${OUTPUT_DIR:-/analysis/output}"

# Fecha calculada AQUÍ, en tiempo de ejecución -- no en el build de la imagen.
# Esto es lo que corrige la carpeta de fecha vieja (2026-09-08) que viste en
# el log, que quedaba fija porque venía de una imagen construida antes.
RUN_DATE="$(date -u +%Y-%m-%d)"

mkdir -p "$OUTPUT_DIR"

echo "=== Iniciando render: $(date -u) ==="
Rscript -e "rmarkdown::render('${RMD_FILE}', output_file = 'analysis.html', output_dir = '${OUTPUT_DIR}')"
echo "=== Render terminado: $(date -u) ==="

echo "=== Subiendo resultados a s3://${S3_BUCKET}/output/${RUN_DATE}/ ==="
aws s3 sync "$OUTPUT_DIR" "s3://${S3_BUCKET}/output/${RUN_DATE}/"
echo "=== Subida completa ==="

if [ "$AUTO_SHUTDOWN" = "true" ]; then
  echo "=== AUTO_SHUTDOWN=true: apagando la instancia EC2 en 60s ==="
  sleep 60

  # 'sudo shutdown' (lo que veías fallar como "command not found") no
  # funciona desde DENTRO del contenedor: no tiene sudo instalado y, aunque
  # lo tuviera, un contenedor no controla el apagado del host EC2. Para
  # apagar la instancia real hay que llamar la API de EC2 desde aquí, y para
  # eso la instancia necesita un IAM Instance Role con permiso
  # ec2:StopInstances (Consola AWS > EC2 > tu instancia > Actions > Security
  # > Modify IAM role).
  INSTANCE_ID="$(curl -sf http://169.254.169.254/latest/meta-data/instance-id || true)"
  REGION="$(curl -sf http://169.254.169.254/latest/meta-data/placement/region || true)"

  if [ -n "$INSTANCE_ID" ] && [ -n "$REGION" ]; then
    echo "Apagando instancia ${INSTANCE_ID} en ${REGION}..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
  else
    echo "No se pudo leer instance-id/region desde el metadata endpoint; no se apagó la instancia."
  fi
fi
