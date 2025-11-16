FROM node:22-alpine AS build-env
WORKDIR /app

COPY package*.json ./

RUN npm ci --omit=dev --ignore-scripts

COPY . .
RUN npm run build && chown -R 65532:65532 dist

FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app

COPY --from=build-env /app/dist ./dist

USER nonroot

EXPOSE 3000

CMD ["dist/main.js"]