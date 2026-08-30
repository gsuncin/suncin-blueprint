/** The access token lives in a module variable and nowhere else.
 *
 * Not localStorage and not a readable cookie: both are reachable from any
 * script on the page, so an XSS walks away with a working credential. In
 * memory it dies with the tab, and the refresh token that outlives it is in an
 * HttpOnly cookie JavaScript cannot read at all.
 *
 * The cost is a refresh on every page load. That is one request.
 */
let accessToken = "";

export const getToken = (): string => accessToken;
export const setToken = (token: string): void => {
  accessToken = token;
};
export const clearSession = (): void => {
  accessToken = "";
};
