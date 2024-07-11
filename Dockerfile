FROM rocker/shiny

RUN apt-get update && \
    apt-get install -y sqlite3 libsqlite3-dev

RUN mkdir /srv/cert_dashboard
RUN mkdir /srv/cert_dashboard/sqlite
RUN mkdir /srv/cert_dashboard/R

WORKDIR /srv/cert_dashboard/R

COPY *.R /srv/cert_dashboard/R/
COPY ./start_files/ /srv/cert_dashboard/R/start_files/

RUN Rscript /srv/cert_dashboard/R/lib.R
