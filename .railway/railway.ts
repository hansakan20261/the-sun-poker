import {
  defineRailway,
  project,
  service,
  postgres,
  redis,
  github,
  preserve,
} from "railway/iac";

export default defineRailway(() => {
  const db = postgres("Postgres");
  const cache = redis("Redis");

  const auth = service("auth", {
    source: github("hansakan20261/the-sun-poker", { branch: "main" }),
    env: {
      RAILWAY_DOCKERFILE_PATH: "services/auth-service/Dockerfile",
      DATABASE_URL: db.env.DATABASE_URL,
      JWT_SECRET: preserve(),
      JWT_EXPIRES_IN: "7d",
      JWT_REFRESH_EXPIRES_IN: "30d",
    },
    healthcheck: "/health",
  });

  const wallet = service("wallet", {
    source: github("hansakan20261/the-sun-poker", { branch: "main" }),
    env: {
      RAILWAY_DOCKERFILE_PATH: "services/wallet-service/Dockerfile",
      DATABASE_URL: db.env.DATABASE_URL,
      REDIS_URL: cache.env.REDIS_URL,
      JWT_SECRET: preserve(),
    },
    healthcheck: "/health",
  });

  const game = service("game", {
    source: github("hansakan20261/the-sun-poker", { branch: "main" }),
    env: {
      RAILWAY_DOCKERFILE_PATH: "services/game-engine/Dockerfile",
      DATABASE_URL: db.env.DATABASE_URL,
      REDIS_URL: cache.env.REDIS_URL,
      JWT_SECRET: preserve(),
    },
    healthcheck: "/health",
  });

  return project("the-sun-poker", {
    resources: [db, cache, auth, wallet, game],
  });
});
