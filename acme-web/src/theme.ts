import { createTheme } from "@mui/material/styles";

/**
 * One theme, two colour schemes.
 *
 * `colorSchemes` gives MUI's CSS-variable mode, which means dark mode follows
 * the OS without a flash of the wrong palette on first paint — a class swap
 * after hydration always shows the wrong one for a frame.
 *
 * Both schemes are defined here, so a colour can never be declared in only one
 * of them and inherit something unreadable in the other.
 */
export const theme = createTheme({
  cssVariables: { colorSchemeSelector: "data-mui-color-scheme" },
  colorSchemes: {
    light: {
      palette: {
        primary: { main: "#1f6f5c" },
        secondary: { main: "#b4581f" },
        background: { default: "#f7f8f7", paper: "#ffffff" },
      },
    },
    dark: {
      palette: {
        // Lifted, not the same hue: a mid-tone that passes contrast on white
        // fails on near-black.
        primary: { main: "#6fc2aa" },
        secondary: { main: "#e8a06a" },
        background: { default: "#121514", paper: "#1b1f1e" },
      },
    },
  },
  shape: { borderRadius: 8 },
  typography: {
    fontFamily: '"Inter", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
    h1: { fontSize: "2rem", fontWeight: 700 },
    h2: { fontSize: "1.5rem", fontWeight: 700 },
    h3: { fontSize: "1.25rem", fontWeight: 600 },
    button: { textTransform: "none", fontWeight: 600 },
  },
  components: {
    MuiButton: { defaultProps: { disableElevation: true } },
    MuiPaper: { defaultProps: { elevation: 0 }, styleOverrides: { root: { backgroundImage: "none" } } },
    MuiTextField: { defaultProps: { size: "small" } },
  },
});
