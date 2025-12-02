# public-app

Public web app template - accessible from internet.

## When to use

- Public websites
- External APIs
- Webhooks from external services

## Deploy

```bash
az acr build --registry <acr> --image public-app:v1 .
az containerapp create -g <rg> --yaml containerapp.yml
```

## Access

Public FQDN with HTTPS: `https://public-app.<id>.<region>.azurecontainerapps.io`

## Local Dev

```bash
npm install
npm start  # http://localhost:3000
```
