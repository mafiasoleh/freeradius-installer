FROM freeradius/freeradius-server:latest
COPY script/raddb/ /etc/raddb/
RUN 