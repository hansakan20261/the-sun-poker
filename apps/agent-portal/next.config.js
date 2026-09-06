/** @type {import('next').NextConfig} */
const AUTH_URL = process.env.AUTH_SERVICE_URL || "http://localhost:3001";
const WALLET_URL = process.env.WALLET_SERVICE_URL || "http://localhost:3002";

const nextConfig = {
  async rewrites() {
    return [
      { source: "/api/auth/:path*", destination: `${AUTH_URL}/auth/:path*` },
      { source: "/api/:path*", destination: `${WALLET_URL}/:path*` },
    ];
  },
};
module.exports = nextConfig;
