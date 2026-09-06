/** @type {import('next').NextConfig} */
const AUTH_URL = process.env.AUTH_SERVICE_URL || "http://localhost:3001";
const WALLET_URL = process.env.WALLET_SERVICE_URL || "http://localhost:3002";
const GAME_URL = process.env.GAME_SERVICE_URL || "http://localhost:3003";

const nextConfig = {
  async rewrites() {
    return [
      { source: "/api/auth/:path*", destination: `${AUTH_URL}/auth/:path*` },
      { source: "/api/wallet/:path*", destination: `${WALLET_URL}/wallet/:path*` },
      { source: "/api/admin/:path*", destination: `${WALLET_URL}/admin/:path*` },
      { source: "/api/settings/:path*", destination: `${WALLET_URL}/settings/:path*` },
      { source: "/api/permissions-menu/:path*", destination: `${WALLET_URL}/permissions-menu/:path*` },
      { source: "/api/clubs/:path*", destination: `${WALLET_URL}/clubs/:path*` },
      { source: "/api/agent-portal/:path*", destination: `${WALLET_URL}/agent-portal/:path*` },
      { source: "/api/game-admin/:path*", destination: `${GAME_URL}/admin/:path*` },
    ];
  },
};
module.exports = nextConfig;
