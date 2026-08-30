# --platform=$BUILDPLATFORM keeps the Node build native on the runner instead of
# emulating the target under QEMU. On a multi-arch build that is the difference
# between one minute and ten.
FROM --platform=$BUILDPLATFORM node:22-alpine AS build

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

# Baked in at build time: Vite inlines these, so they cannot be changed by an
# env var at runtime. A different value means a different image.
ARG VITE_API_URL=/api
ENV VITE_API_URL=$VITE_API_URL

RUN npm run build


# nginx-unprivileged rather than stock nginx: the stock image runs its master
# process as root, which is more than a static file server needs.
FROM nginxinc/nginx-unprivileged:1.29-alpine AS runtime

COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1
