#!/bin/bash
set -euo pipefail

# Variables esperadas (se pasan con -e en el docker run):
#   S3_DATA_BUCKET   bucket donde están los 3 archivos de entrada (.shared, .taxonomy, .xlsx)
#   S3_DATA_PREFIX   carpeta dentro de ese bucket, ej. microvap/input
#   S3_BUCKET        bucket donde subir los resultados
#   S3_PREFIX        carpeta dentro del bucket de resultados, ej. microvap/2026-09-08
#   OUTPUT_FORMAT    "html_document" (default) o "pdf_document"
#   AUTO_SHUTDOWN    "true" para apagar la instancia EC2 al terminar (default: false)
#
# Autenticación con S3: NO se pasan llaves aquí. Si el EC2 tiene un IAM role
# con permisos sobre los buckets, aws-cli las toma automáticamente. Si estás
# probando localmente (no en EC2), exporta AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION antes del docker run.

OUTPUT_FORMAT="${OUTPUT_FORMAT:-html_document}"
DATA_DIR="${DATA_DIR:-/analysis/data}"
OUTPUT_DIR="${OUTPUT_DIR:-/analysis/output}"

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

Rscript -e "rmarkdown::render('analysis.Rmd', output_format = '${OUTPUT_FORMAT}', output_dir = '.')"

echo "=== Render terminado: $(date) ==="

if [ -n "${S3_BUCKET:-}" ]; then
  DEST="s3://${S3_BUCKET}/${S3_PREFIX:-resultados}/"
  echo "=== Subiendo resultados a $DEST ==="

  # Carpeta de figuras/tablas (output_dir dentro del .Rmd)
  aws s3 cp "$OUTPUT_DIR" "$DEST" --recursive

  # El documento knitteado (html o pdf) queda en /analysis
  aws s3 cp . "$DEST" --recursive --exclude "*" --include "analysis.html" --include "analysis.pdf"

  echo "=== Subida completa ==="
else
  echo "AVISO: S3_BUCKET no está definido, no se subió nada. Resultados quedan en el contenedor."
fi

if [ "${AUTO_SHUTDOWN:-false}" = "true" ]; then
  echo "=== AUTO_SHUTDOWN=true: apagando la instancia EC2 en 60s ==="
  sleep 60
  sudo shutdown -h now
fi
