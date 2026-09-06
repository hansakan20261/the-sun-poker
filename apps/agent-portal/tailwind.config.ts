import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./lib/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        sun: {
          red: "#8B0000",
          "red-dark": "#5C0000",
          "red-light": "#B22222",
          gold: "#DAA520",
          "gold-light": "#FFD700",
          black: "#1A1A1A",
          green: "#2E8B57",
        },
      },
    },
  },
  plugins: [],
};
export default config;
