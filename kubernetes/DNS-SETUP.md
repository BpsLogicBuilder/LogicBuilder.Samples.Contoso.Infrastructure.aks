# DNS Configuration for Host-Based Ingress

This guide explains how to configure DNS for host-based routing with NGINX Ingress Controller.

## Overview

With host-based routing, each service gets its own hostname/subdomain, all pointing to the **same external IP** (20.15.57.117):

- `contoso.yourdomain.com` → Angular Frontend
- `contoso-api.yourdomain.com` → CRUD API
- `contoso-spa-api.yourdomain.com` → Workflow API
- `contoso-kendo-grid-api.yourdomain.com` → Kendo Grid API

## Option 1: Azure DNS Zone (Production)

### Step 1: Create an Azure DNS Zone

```powershell
# Create DNS zone
az network dns zone create \
  --resource-group rg-contoso-aks \
  --name yourdomain.com

# Get nameservers (you'll need these to update your domain registrar)
az network dns zone show \
  --resource-group rg-contoso-aks \
  --name yourdomain.com \
  --query nameServers
```

### Step 2: Create DNS A Records

```powershell
$EXTERNAL_IP = "20.15.57.117"
$RESOURCE_GROUP = "rg-contoso-aks"
$DNS_ZONE = "yourdomain.com"

# Main frontend
az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DNS_ZONE \
  --record-set-name contoso \
  --ipv4-address $EXTERNAL_IP

# API endpoints
az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DNS_ZONE \
  --record-set-name contoso-api \
  --ipv4-address $EXTERNAL_IP

az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DNS_ZONE \
  --record-set-name contoso-spa-api \
  --ipv4-address $EXTERNAL_IP

az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DNS_ZONE \
  --record-set-name contoso-kendo-grid-api \
  --ipv4-address $EXTERNAL_IP
```

### Step 3: Update Domain Registrar

Update your domain registrar's nameservers to point to the Azure DNS nameservers from Step 1.

---

## Option 2: Azure DNS with Wildcard (Simpler)

Instead of individual A records, use a wildcard record:

```powershell
$EXTERNAL_IP = "20.15.57.117"
$RESOURCE_GROUP = "rg-contoso-aks"
$DNS_ZONE = "yourdomain.com"

# Wildcard record for all subdomains
az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DNS_ZONE \
  --record-set-name "*" \
  --ipv4-address $EXTERNAL_IP

# Root domain for main app
az network dns record-set a add-record \
  --resource-group $RESOURCE_GROUP \
  --zone-name $DNS_ZONE \
  --record-set-name "@" \
  --ipv4-address $EXTERNAL_IP
```

This approach allows `*.yourdomain.com` to resolve to your ingress IP.

---

## Option 3: nip.io (Testing/Demo - No DNS Required!)

For testing without DNS configuration, use [nip.io](https://nip.io), which provides wildcard DNS for any IP:

### Update ingress to use nip.io hostnames:

```yaml
# Example: contoso-api.20.15.57.117.nip.io automatically resolves to 20.15.57.117
rules:
- host: contoso-api.20.15.57.117.nip.io
  http:
    paths:
    - path: /
      pathType: Prefix
      backend:
        service:
          name: contoso-api
          port:
            number: 8080
```

**Your URLs would be:**
- `http://contoso.20.15.57.117.nip.io` → Angular
- `http://contoso-api.20.15.57.117.nip.io` → CRUD API
- `http://contoso-spa-api.20.15.57.117.nip.io` → Workflow API
- `http://contoso-kendo-grid-api.20.15.57.117.nip.io` → Kendo Grid API

**Advantages:**
- ✅ No DNS configuration needed
- ✅ Works immediately
- ✅ Great for testing/demos

**Disadvantages:**
- ❌ Longer URLs
- ❌ Dependent on external service
- ❌ Not suitable for production

---

## Option 4: Local Hosts File (Development Only)

For local development/testing, edit your hosts file:

### Windows
Edit `C:\Windows\System32\drivers\etc\hosts` (requires admin):

```
20.15.57.117 contoso.local
20.15.57.117 contoso-api.local
20.15.57.117 contoso-spa-api.local
20.15.57.117 contoso-kendo-grid-api.local
```

### Linux/Mac
Edit `/etc/hosts` (requires sudo):

```bash
sudo nano /etc/hosts
# Add the same entries as above
```

**Your URLs would be:**
- `http://contoso.local`
- `http://contoso-api.local/weatherforecast`
- etc.

**Note:** Update ingress hostnames to use `.local` domain instead of `.yourdomain.com`

---

## Verification

After DNS is configured, verify with:

```powershell
# Check DNS resolution
nslookup contoso-api.yourdomain.com

# Test endpoint
Invoke-WebRequest -Uri "http://contoso-api.yourdomain.com/weatherforecast" -UseBasicParsing

# Test with specific Host header (before DNS propagation)
curl -H "Host: contoso-api.yourdomain.com" http://20.15.57.117/weatherforecast
```

---

## DNS Propagation Time

- **Azure DNS:** Changes are usually propagated within 60 seconds
- **External DNS providers:** Can take 24-48 hours for full global propagation
- **Local hosts file:** Immediate (may need to flush DNS cache)

### Flush DNS Cache (Windows)
```powershell
ipconfig /flushdns
```

---

## Update Angular Environment Variables

After switching to host-based routing, update your Angular deployment:

```yaml
env:
- name: WORKFLOW_URL
  value: "http://contoso-spa-api.yourdomain.com"  # or .nip.io or .local
- name: CRUD_URL
  value: "http://contoso-api.yourdomain.com"
- name: GRID_URL
  value: "http://contoso-kendo-grid-api.yourdomain.com"
```

---

## Recommended Approach

1. **Development/Testing:** Use **nip.io** (Option 3) - zero configuration
2. **Production:** Use **Azure DNS with Wildcard** (Option 2) - simplest production setup
3. **Enterprise:** Use **Azure DNS with individual A records** (Option 1) - most control

---

## Benefits of Host-Based Routing

✅ **No URL rewriting needed** - cleaner configuration  
✅ **Better API design** - `http://api.domain.com/endpoint` vs `http://domain.com/api/endpoint`  
✅ **Easier CORS** - each service has its own origin  
✅ **SSL certificates** - can use wildcard cert `*.yourdomain.com`  
✅ **Matches Azure Container Apps model** - easier migration path  
✅ **Independent scaling** - can move services to different clusters without changing URLs  

---

## Quick Start with nip.io

To try host-based routing right now without any DNS setup:

```powershell
# 1. Update ingress file with nip.io hostnames
# Edit kubernetes/deployments-host-based.yaml
# Replace "yourdomain.com" with "20.15.57.117.nip.io"

# 2. Apply the configuration
kubectl apply -f kubernetes/deployments-host-based-nip.yaml

# 3. Test immediately
curl http://contoso-api.20.15.57.117.nip.io/weatherforecast
```
