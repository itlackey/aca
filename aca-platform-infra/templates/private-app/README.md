# private-app

Private web app template - VNet only (10.x IP).

## When to use

- Intranet applications
- Internal APIs
- Backend services called by other apps

## Deploy

```bash
az acr build --registry <acr> --image private-app:v1 .
az containerapp create -g <rg> --yaml containerapp.yml
```

## Access

**Not accessible from internet.** Access options:

1. **From within VNet**: Use internal FQDN
   ```
   http://private-app.internal.<env-id>.<region>.azurecontainerapps.io
   ```

2. **From on-prem via VPN/ExpressRoute**:
   - Get environment's static IP: `az containerapp env show -n <env> -g <rg> --query properties.staticIp`
   - Configure on-prem DNS to resolve to this IP

3. **From other container apps**: Use internal FQDN directly

## Local Dev

```bash
npm install
npm start  # http://localhost:3000
```
