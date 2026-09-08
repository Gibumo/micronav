FROM rocker/verse:4.4.1
# rocker/verse ya trae: R, tidyverse, rmarkdown, pandoc y tinytex (LaTeX
# liviano) -- eso cubre pdf_document y html_document sin instalar TeX Live
# completo (~4GB). Si nunca usas el output PDF, cambia a rocker/tidyverse
# para una imagen más liviana.

# Librerías de sistema que necesitan los paquetes de R que faltan
# (mvabund compila C++/Fortran; caret/randomForest no piden nada extra)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    gfortran \
    libopenblas-dev \
    awscli \
    && rm -rf /var/lib/apt/lists/*

# Paquetes de CRAN que no vienen en rocker/verse
RUN R -e "install.packages(c( \
      'vegan', 'ggpubr', 'mvabund', 'openxlsx', 'readxl', 'tableone', \
      'matrixStats', 'cowplot', 'patchwork', 'randomForest', 'caret', \
      'pROC', 'car', 'rstatix', 'FSA', 'ggtext' \
    ), repos = 'https://cloud.r-project.org', Ncpus = parallel::detectCores())"

WORKDIR /analysis

# El .Rmd y el script de render/subida se copian al construir la imagen.
# Los DATOS (los 3 archivos de /1 - Equipo/Descargas/dickson) NO se copian
# aquí -- se montan como volumen en el docker run (ver comando abajo),
# así puedes reusar la misma imagen con datos distintos sin reconstruirla.
COPY analysis.Rmd .
COPY render_and_upload.sh .
RUN chmod +x render_and_upload.sh

ENTRYPOINT ["./render_and_upload.sh"]
