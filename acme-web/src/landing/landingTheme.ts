import { createTheme } from "@mui/material/styles";

/**
 * A separate theme from the app's, on purpose.
 *
 * The two have opposite jobs: the app is operationally dense and read all day,
 * the landing page is read once by someone deciding whether to care. Sharing a
 * theme means every marketing tweak risks the application's density, and every
 * density fix flattens the marketing page.
 *
 * It also keeps `src/theme.ts` out of the landing bundle.
 */
export const landingTheme = createTheme({
  cssVariables: { colorSchemeSelector: "data-mui-color-scheme" },
  colorSchemes: {
    light: {
      palette: {
        primary: { main: "#14504a" },
        background: { default: "#fbfaf7", paper: "#ffffff" },
        text: { primary: "#14201d", secondary: "#4a5754" },
      },
    },
    dark: {
      palette: {
        primary: { main: "#7fd0bd" },
        background: { default: "#0e1211", paper: "#161b1a" },
        text: { primary: "#eef2f1", secondary: "#a7b4b1" },
      },
    },
  },
  typography: {
    fontFamily: 'system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
    h1: { fontSize: "clamp(2.25rem, 5vw, 3.5rem)", fontWeight: 800, lineHeight: 1.1 },
    h2: { fontSize: "clamp(1.5rem, 3vw, 2rem)", fontWeight: 700 },
    h3: { fontSize: "1.125rem", fontWeight: 600 },
    button: { textTransform: "none", fontWeight: 600 },
  },
  shape: { borderRadius: 10 },
});
