FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN addgroup -S non-root && adduser -S non-root -G non-root \
    && chown -R non-root:non-root /usr/share/nginx/html \
    && chown -R non-root:non-root /var/cache/nginx \
    && chown -R non-root:non-root /var/log/nginx \
    && touch /var/run/nginx.pid \
    && chown non-root:non-root /var/run/nginx.pid

EXPOSE 80
USER non-root
CMD ["nginx", "-g", "daemon off;"]
