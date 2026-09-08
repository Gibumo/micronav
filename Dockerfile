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

# Paquetes de CRAN que no vienen en rocker/verse.
# Reintenta hasta 3 veces los paquetes que falten (los tropiezos de red/mirror
# de CRAN durante el build, como con la dependencia 'Deriv', suelen ser
# momentáneos y se resuelven solos en un segundo intento). Si después de 3
# intentos algo sigue faltando, el "docker build" falla con la lista exacta.
RUN R -e " \
      pkgs <- c('vegan', 'ggpubr', 'mvabund', 'openxlsx', 'readxl', 'tableone', \
                'matrixStats', 'cowplot', 'patchwork', 'randomForest', 'caret', \
                'pROC', 'car', 'rstatix', 'FSA', 'ggtext', 'data.table'); \
      for (i in 1:3) { \
        falta <- pkgs[!(pkgs %in% rownames(installed.packages()))]; \
        if (length(falta) == 0) break; \
        message('Intento ', i, ' -- instalando: ', paste(falta, collapse = ', ')); \
        install.packages(falta, repos = 'https://cloud.r-project.org', \
                          Ncpus = parallel::detectCores()); \
      }; \
      falta <- pkgs[!(pkgs %in% rownames(installed.packages()))]; \
      if (length(falta) > 0) stop('No se instalaron: ', paste(falta, collapse = ', ')) \
    "

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
