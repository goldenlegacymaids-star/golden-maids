import type { Metadata } from "next";

import { AuthProvider } from "@/lib/auth";

import { inter, poppins } from "./fonts";
import "./globals.css";

export const metadata: Metadata = {
  title: "Golden Maids Staff",
  description: "Golden Legacy Domestic Workers Services – staff website.",
  // Staff-only: keep it out of search engines.
  robots: { index: false, follow: false },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={`${inter.variable} ${poppins.variable}`}>
      <body className="min-h-screen font-sans antialiased">
        <AuthProvider>{children}</AuthProvider>
      </body>
    </html>
  );
}
