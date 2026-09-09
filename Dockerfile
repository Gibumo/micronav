FROM rocker/verse:4.4.1
# rocker/verse ya trae: R, tidyverse, rmarkdown, pandoc y tinytex (LaTeX
# liviano) -- eso cubre pdf_document y html_document sin instalar TeX Live
# completo (~4GB). Si nunca usas el output PDF, cambia a rocker/tidyverse
# para una imagen más liviana.

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    gfortran \
    libopenblas-dev \
    libgsl-dev \
    awscli \
    && rm -rf /var/lib/apt/lists/*

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

RUN R -e "install.packages(c('xfun', 'knitr', 'rmarkdown', 'evaluate'), \
      repos = 'https://cloud.r-project.org')"

WORKDIR /analysis

COPY analysis.Rmd .
COPY render_and_upload.sh .
RUN chmod +x render_and_upload.sh

ENTRYPOINT ["./render_and_upload.sh"]
