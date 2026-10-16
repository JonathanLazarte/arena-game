FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json* tsconfig.json ./
RUN npm ci || npm install
COPY src ./src
COPY test ./test
RUN npx tsc -p .

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/dist/src ./dist/src
COPY package.json ./
ENV PORT=47800
EXPOSE 47800/udp
USER node
CMD ["node", "dist/src/index.js"]
