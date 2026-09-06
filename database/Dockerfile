FROM postgres:16-alpine

WORKDIR /app
COPY database/init ./init
COPY database/run-init.sh ./run-init.sh

RUN chmod +x ./run-init.sh

CMD ["./run-init.sh"]
