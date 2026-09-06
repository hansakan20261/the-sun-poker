FROM node:20-alpine

WORKDIR /app

COPY services/wallet-service/package*.json services/wallet-service/
RUN cd services/wallet-service && npm ci --omit=dev

COPY config ./config
COPY services/wallet-service/src ./services/wallet-service/src

ENV PORT=3002
EXPOSE 3002

CMD ["node", "services/wallet-service/src/index.js"]
