#!/bin/bash
set -euo pipefail

# Variables esperadas (en el .env):
#   S3_DATA_BUCKET   bucket donde están los 3 archivos de entrada (.shared, .taxonomy, .xlsx)
#   S3_DATA_PREFIX   carpeta dentro de ese bucket, ej. dickson
#   S3_BUCKET        bucket donde subir los resultados
#   OUTPUT_FORMAT    "html_document" (default) o "pdf_document"
#   AUTO_SHUTDOWN    "true" para apagar la instancia EC2 al terminar (default: false)
#
# Autenticación con S3: NO se pasan llaves aquí si el EC2 tiene un IAM role
# con permisos sobre los buckets (y, si usas AUTO_SHUTDOWN, ec2:StopInstances)
# -- aws-cli las toma automáticamente. Si pruebas fuera de un EC2 con role,
# exporta AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
# antes del docker run.

# --- CAMBIO --- nombre de archivo actualizado (antes: analysis.Rmd)
RMD_FILE="comparison_samples_09092026.Rmd"
# --- FIN CAMBIO ---

OUTPUT_FORMAT="${OUTPUT_FORMAT:-html_document}"
export DATA_DIR="${DATA_DIR:-/analysis/data}"
export OUTPUT_DIR="${OUTPUT_DIR:-/analysis/output}"

# --- CAMBIO ---
# La carpeta de fecha en S3 ahora se calcula SIEMPRE aquí, al momento de
# correr -- ya no depende de que alguien edite S3_PREFIX a mano en el .env
# antes de cada corrida. Eso fue justo lo que causó la carpeta vieja
# "2026-09-08": quedó puesta a mano y nadie la actualizó la vez siguiente.
# Si algún día necesitas reprocesar y subir a una carpeta de fecha vieja
# a propósito, dímelo y le agregamos una variable de override explícita
# en vez de tener que volver a tocar esto.
RUN_DATE="$(date -u +%Y-%m-%d)"
S3_PREFIX="output/${RUN_DATE}"
# --- FIN CAMBIO ---

mkdir -p "$DATA_DIR" "$OUTPUT_DIR"

if [ -n "${S3_DATA_BUCKET:-}" ]; then
  SRC="s3://${S3_DATA_BUCKET}/${S3_DATA_PREFIX:-}"
  echo "=== Descargando datos de entrada desde $SRC ==="
  aws s3 sync "$SRC" "$DATA_DIR"
  echo "=== Datos descargados: ==="
  ls -la "$DATA_DIR"
else
  echo "AVISO: S3_DATA_BUCKET no está definido, se usará lo que ya haya en $DATA_DIR"
fi

echo "=== Iniciando render: $(date) ==="
echo "Formato de salida: $OUTPUT_FORMAT"

Rscript -e "rmarkdown::render('${RMD_FILE}', output_format = '${OUTPUT_FORMAT}', output_dir = '.')"

echo "=== Render terminado: $(date) ==="

if [ -n "${S3_BUCKET:-}" ]; then
  DEST="s3://${S3_BUCKET}/${S3_PREFIX}/"
  echo "=== Subiendo resultados a $DEST ==="

  # Carpeta de figuras/tablas (output_dir dentro del .Rmd)
  aws s3 cp "$OUTPUT_DIR" "$DEST" --recursive

  # El documento knitteado (html o pdf) queda en /analysis
  aws s3 cp . "$DEST" --recursive --exclude "*" --include "analysis.html" --include "analysis.pdf"

  echo "=== Subida completa ==="
fi

# --- CAMBIO ---
# 'sudo shutdown' nunca funcionaba desde dentro del contenedor -- no tiene
# sudo instalado y, aunque lo tuviera, un contenedor no controla el apagado
# del host EC2. Por eso veías "sudo: shutdown: command not found" en el log.
# Reemplazado por la API real de EC2. Requiere que el IAM role de la
# instancia tenga permiso ec2:StopInstances (Consola AWS > EC2 > tu
# instancia > Actions > Security > Modify IAM role).
if [ "${AUTO_SHUTDOWN:-false}" = "true" ]; then
  echo "=== AUTO_SHUTDOWN=true: apagando la instancia EC2 en 60s ==="
  sleep 60
  INSTANCE_ID="$(curl -sf http://169.254.169.254/latest/meta-data/instance-id || true)"
  REGION="$(curl -sf http://169.254.169.254/latest/meta-data/placement/region || true)"
  if [ -n "$INSTANCE_ID" ] && [ -n "$REGION" ]; then
    echo "Apagando instancia ${INSTANCE_ID} en ${REGION}..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --region "$REGION"
  else
    echo "No se pudo leer instance-id/region desde el metadata endpoint; no se apagó la instancia."
  fi
fi
# --- FIN CAMBIO ---
