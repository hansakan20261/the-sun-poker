import "./globals.css";
export const metadata = { title: "THE SUN POKER — Agent Portal" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="th"><body>{children}</body></html>;
}
