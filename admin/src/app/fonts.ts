import localFont from "next/font/local";

// Bundled with the site (SIL Open Font Licence, see src/fonts/OFL-*.txt).
export const inter = localFont({
  src: [
    { path: "../fonts/Inter-Regular.ttf", weight: "400" },
    { path: "../fonts/Inter-Medium.ttf", weight: "500" },
    { path: "../fonts/Inter-SemiBold.ttf", weight: "600" },
  ],
  variable: "--font-inter",
  display: "swap",
});

export const poppins = localFont({
  src: [
    { path: "../fonts/Poppins-Medium.ttf", weight: "500" },
    { path: "../fonts/Poppins-SemiBold.ttf", weight: "600" },
    { path: "../fonts/Poppins-Bold.ttf", weight: "700" },
  ],
  variable: "--font-poppins",
  display: "swap",
});
