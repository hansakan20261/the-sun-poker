function corsOriginConfig() {
  const configured = (process.env.CORS_ORIGINS || '')
    .split(',')
    .map(origin => origin.trim())
    .filter(Boolean);
  if (configured.includes('*')) return true;
  if (process.env.NODE_ENV === 'production' && configured.length === 0) {
    throw new Error('CORS_ORIGINS must be configured in production');
  }
  return configured.length ? configured : true;
}

module.exports = { corsOriginConfig };
