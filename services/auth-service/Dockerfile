FROM node:20-alpine

WORKDIR /app

COPY services/auth-service/package*.json services/auth-service/
RUN cd services/auth-service && npm ci --omit=dev

COPY config ./config
COPY services/auth-service/src ./services/auth-service/src

ENV PORT=3001
EXPOSE 3001

CMD ["node", "services/auth-service/src/index.js"]
