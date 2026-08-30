/** The landing page's byte budget.
 *
 * Every kilobyte here is paid for by a visitor who has not decided to care
 * yet, on whatever connection they happen to be on. A budget is the only thing
 * that keeps that number from drifting upward one convenient import at a time
 * — and the usual way it drifts is someone reaching into the app's code for a
 * component, dragging the router or the query client along with it.
 *
 * Raising this is a deliberate decision, not a fix for a failing test.
 *
 * WHERE IT CURRENTLY GOES: about 300 KB of the ~325 KB baseline is MUI, pulled
 * in by ThemeProvider, Container, Grid and Typography. That is a lot for a page
 * with no interactivity, and it is the first thing to attack if this budget
 * starts to bind — a landing page built from plain elements and a stylesheet
 * would come in under 30 KB. The boilerplate keeps MUI here so the page shares
 * the app's design language out of the box, not because it is the right
 * long-term answer.
 */
export const LANDING_JS_BUDGET_BYTES = 400 * 1024;
