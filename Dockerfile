FROM rocker/verse:4.5.3
# R 4.5.3 (no 4.4.x) porque 'Deriv' -- dependencia de 'doBy', que a su vez
# necesitan varios paquetes de la lista de abajo -- ya exige R >= 4.5 en su
# versión actual de CRAN. rocker/verse ya trae: tidyverse, rmarkdown, pandoc
# y tinytex (LaTeX liviano), cubriendo pdf_document y html_document sin
# instalar TeX Live completo (~4GB).

# Librerías de sistema que necesitan los paquetes de R que faltan
# (mvabund compila C++/Fortran; caret/randomForest no piden nada extra)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    gfortran \
    libopenblas-dev \
    libgsl-dev \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 -- el paquete 'awscli' de apt ya no existe en Ubuntu 24.04
# (noble), así que se instala con el instalador oficial de AWS en vez de apt.
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# 'Deriv' aparte primero, en su propia capa -- con verificación real de que
# quedó instalado (y no solo "el comando corrió"), más tiempo de espera por
# si la red del EC2 anda lenta con este paquete puntual.
RUN for i in 1 2 3; do \
      echo "=== Intento $i instalando Deriv ==="; \
      Rscript -e "options(timeout = 300); \
        if (!('Deriv' %in% rownames(installed.packages()))) \
          install.packages('Deriv', repos = 'https://cloud.r-project.org'); \
        if (!('Deriv' %in% rownames(installed.packages()))) quit(status = 1)" \
      && break; \
      echo "Intento $i de Deriv falló, reintentando en 5s..."; \
      sleep 5; \
    done; \
    Rscript -e "if (!('Deriv' %in% rownames(installed.packages()))) stop('Deriv no se pudo instalar')"

# Paquetes de CRAN que no vienen en rocker/verse.
# Reintenta hasta 3 veces, cada intento en un PROCESO DE R NUEVO (no un loop
# dentro de la misma sesión) -- así cada intento vuelve a consultar el índice
# de CRAN desde cero en vez de reusar una lista cacheada que puede haber
# quedado incompleta por un tropiezo de red momentáneo.
RUN for i in 1 2 3; do \
      echo "=== Intento $i de instalación de paquetes ==="; \
      Rscript -e " \
        pkgs <- c('vegan', 'ggpubr', 'mvabund', 'openxlsx', 'readxl', 'tableone', \
                  'matrixStats', 'cowplot', 'patchwork', 'randomForest', 'caret', \
                  'pROC', 'car', 'rstatix', 'FSA', 'ggtext', 'data.table'); \
        falta <- pkgs[!(pkgs %in% rownames(installed.packages()))]; \
        if (length(falta) > 0) install.packages(falta, repos = 'https://cloud.r-project.org', \
                          Ncpus = parallel::detectCores()); \
        falta <- pkgs[!(pkgs %in% rownames(installed.packages()))]; \
        if (length(falta) > 0) { message('Faltan: ', paste(falta, collapse=', ')); quit(status = 1) }" \
      && break; \
      echo "Intento $i falló, reintentando en 5s..."; \
      sleep 5; \
    done; \
    Rscript -e " \
      pkgs <- c('vegan', 'ggpubr', 'mvabund', 'openxlsx', 'readxl', 'tableone', \
                'matrixStats', 'cowplot', 'patchwork', 'randomForest', 'caret', \
                'pROC', 'car', 'rstatix', 'FSA', 'ggtext', 'data.table'); \
      falta <- pkgs[!(pkgs %in% rownames(installed.packages()))]; \
      if (length(falta) > 0) stop('No se instalaron: ', paste(falta, collapse = ', '))"

# Re-instala xfun/knitr/rmarkdown/evaluate JUNTOS al final, para que queden
# en versiones mutuamente compatibles. Sin esto, instalar los paquetes de
# arriba puede actualizar una dependencia de knitr sin tocar xfun y produce
# el error "object 'attr' is not exported by 'namespace:xfun'" al renderizar.
RUN R -e "install.packages(c('xfun', 'knitr', 'rmarkdown', 'evaluate'), \
      repos = 'https://cloud.r-project.org')"

WORKDIR /analysis

# El .Rmd y el script de render/subida se copian al construir la imagen.
# Los DATOS (los 3 archivos de /1 - Equipo/Descargas/dickson) NO se copian
# aquí -- se montan como volumen en el docker run (ver comando abajo),
# así puedes reusar la misma imagen con datos distintos sin reconstruirla.
COPY analysis.Rmd .
COPY render_and_upload.sh .
RUN chmod +x render_and_upload.sh

ENTRYPOINT ["./render_and_upload.sh"]
