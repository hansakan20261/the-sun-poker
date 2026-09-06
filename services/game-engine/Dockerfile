FROM node:20-alpine

WORKDIR /app

COPY services/game-engine/package*.json services/game-engine/
RUN cd services/game-engine && npm ci --omit=dev

COPY config ./config
COPY services/game-engine/src ./services/game-engine/src

ENV PORT=3003
EXPOSE 3003

CMD ["node", "services/game-engine/src/index.js"]
