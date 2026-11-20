# Cloudflare Tunnel (`cloudflared`) & Hosting New Services

This stack runs `cloudflare/cloudflared` inside K3s (`replicas: 2`) and forwards all `*.francvok.from.hr` traffic to the cluster's Traefik Ingress controller (`http://traefik.kube-system.svc.cluster.local:80`).

Because [config.yaml](./config.yaml) uses a wildcard ingress rule (`*.francvok.from.hr`), **adding a new K3s service only requires deploying a Kubernetes `Ingress`—no changes to Cloudflare DNS or `cloudflared` are needed.**

---

## 1. One-Time Tunnel & Wildcard DNS Setup

Run these steps once when initially provisioning the `cloudflared` stack:

1. **Create a dedicated K3s tunnel** (separate from your host `pc-dev` tunnel) and point the wildcard DNS record to it:
   ```bash
   cloudflared tunnel create k3s-traefik
   cloudflared tunnel route dns k3s-traefik "*.francvok.from.hr"
   ```
   - Exact DNS records take precedence over `*`. Delete any legacy `CNAME` records (`kupa`, `home`, `atuin`) in Cloudflare DNS that still point to `pc-dev` so they fall through to `*`.
   - Keep host-only records (`ssh`, `webhook`, `kuma`, `treblle`, `ofadin`, `talents`, `wfrp5e`) pointing to `pc-dev`.
   - In Cloudflare **SSL/TLS -> Overview**, use **Full** or **Full (strict)** (never *Flexible*, which causes redirect loops).

2. **Create `cloudflared/.env` and deploy the stack:**
   ```bash
   cp cloudflared/example.env cloudflared/.env
   # Fill in CF_TUNNEL_ID and CF_CREDENTIALS_JSON_B64:
   #   base64 -w0 ~/.cloudflared/<CF_TUNNEL_ID>.json
   ./deploy.sh ./cloudflared
   ```

3. **Verify the tunnel pods are connected:**
   ```bash
   kubectl get pods -n cloudflared
   kubectl logs -n cloudflared deploy/cloudflared -f
   ```

---

## 2. How to Add a New Hosted Service

1. **Create a stack directory** following the repo's 3-phase convention (see [../README.md](../README.md)):
   ```text
   <app>/
   ├── 00-namespace.yaml     # Phase 1: Dedicated Namespace
   ├── 10-environment.yaml   # Phase 2 (optional): Secret template + .env
   └── 20-<app>.yaml         # Phase 3: (PVC +) Deployment + Service + Ingress
   ```

2. **Define the `Service` and `Ingress`** in `20-<app>.yaml` (or `30-<app>.yaml`) with a **single-level** subdomain under `.francvok.from.hr` (Cloudflare Free Universal SSL covers `*.francvok.from.hr`, not nested `a.b.francvok.from.hr`):
   ```yaml
   apiVersion: v1
   kind: Service
   metadata:
     name: myapp-svc
     namespace: myapp
   spec:
     selector:
       app: myapp
     ports:
       - protocol: TCP
         port: 80
         targetPort: 8080 # containerPort of your app
   ---
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: myapp-ingress
     namespace: myapp
   spec:
     rules:
       - host: myapp.francvok.from.hr
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: myapp-svc
                   port:
                     number: 80
   ```

3. **Deploy the new stack:**
   ```bash
   ./deploy.sh ./myapp
   ```

4. **Verify pods and Ingress:**
   ```bash
   kubectl get pods,pvc,svc,ingress -n myapp
   ```
   `https://myapp.francvok.from.hr` will route automatically through Cloudflare -> `cloudflared` -> Traefik -> `myapp-svc`.

---

## 3. Editing `cloudflared/config.yaml`

If you change [config.yaml](./config.yaml) (for example, to add another domain or custom route above `- service: http_status:404`), re-sync the `ConfigMap` and restart the Deployment so pods load the new file:

```bash
./deploy.sh ./cloudflared
kubectl rollout restart deployment/cloudflared -n cloudflared
```

---

## 4. Useful Troubleshooting Commands

```bash
# List all Ingress hostnames across all namespaces
kubectl get ingress -A

# Check Traefik service name & port in kube-system
kubectl get svc -n kube-system traefik

# Check cloudflared readiness and tunnel connection logs
kubectl get pods -n cloudflared
kubectl logs -n cloudflared deploy/cloudflared --tail=100
```
