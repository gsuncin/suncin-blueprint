/** Static content injected into landing.html at build time by a Vite plugin.
 *
 * Kept as plain strings, not JSX: this has to exist in the HTML before any
 * JavaScript runs, and it is read by crawlers and by anyone who blocks
 * scripts. A React component could not be rendered at that point.
 */

export const NOSCRIPT_FALLBACK_STYLESHEET = `
  #root { display: none; }
  .noscript-fallback {
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    max-width: 42rem; margin: 4rem auto; padding: 0 1.5rem; line-height: 1.6;
  }
  .noscript-fallback h1 { font-size: 2rem; margin-bottom: .5rem; }
`.trim();

export const LANDING_HEADLINE = "Ship the boring parts once";
export const LANDING_SUBHEAD =
  "A monorepo template with a gateway, a BFF, a stateless service, and the deployment that carries them.";

export function renderNoscriptFallbackHtml(): string {
  return `
    <div class="noscript-fallback">
      <h1>${LANDING_HEADLINE}</h1>
      <p>${LANDING_SUBHEAD}</p>
      <p><a href="/login">Sign in</a></p>
    </div>
  `.trim();
}
