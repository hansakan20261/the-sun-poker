import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "THE SUN POKER — Admin",
  description: "Admin Back-office",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="th">
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
      </head>
      <body>{children}</body>
    </html>
  );
}
