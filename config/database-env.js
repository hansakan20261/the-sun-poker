function databaseConfigFromEnv() {
  if (process.env.DATABASE_URL) {
    const ssl = process.env.DB_SSL === 'true'
      ? { rejectUnauthorized: false }
      : undefined;
    return { connectionString: process.env.DATABASE_URL, ssl };
  }
  return {
    host: process.env.DB_HOST,
    port: process.env.DB_PORT,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
  };
}

module.exports = { databaseConfigFromEnv };
