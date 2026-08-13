# Sample Dockerfiles for Applications

This directory contains reference Dockerfile templates for each application type.

## Angular Frontend (Node.js)

**File: `Dockerfile.angular`**

```dockerfile
# Build stage
FROM node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build the Angular application
RUN npm run build -- --configuration production

# Production stage
FROM nginx:alpine

# Copy custom nginx config (optional)
# COPY nginx.conf /etc/nginx/nginx.conf

# Copy built application
COPY --from=build /app/dist/angular-frontend /usr/share/nginx/html

# Expose port
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost/ || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

**nginx.conf (for CORS support):**
```nginx
server {
    listen 80;
    server_name localhost;
    root /usr/share/nginx/html;
    index index.html;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    location / {
        try_files $uri $uri/ /index.html;
        
        # CORS headers (if needed)
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

## ASP.NET Core API (Workflow Service, Frontend APIs, Backend APIs)

**File: `Dockerfile.dotnet`**

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

# Copy csproj and restore dependencies
COPY ["WorkflowService/WorkflowService.csproj", "WorkflowService/"]
RUN dotnet restore "WorkflowService/WorkflowService.csproj"

# Copy everything else and build
COPY . .
WORKDIR "/src/WorkflowService"
RUN dotnet build "WorkflowService.csproj" -c Release -o /app/build

# Publish stage
FROM build AS publish
RUN dotnet publish "WorkflowService.csproj" -c Release -o /app/publish /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final

WORKDIR /app

# Create a non-root user
RUN adduser --disabled-password --gecos '' appuser && chown -R appuser /app
USER appuser

# Copy published application
COPY --from=publish /app/publish .

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Environment variables
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "WorkflowService.dll"]
```

## Node.js API (Alternative for Frontend/Backend APIs)

**File: `Dockerfile.nodejs`**

```dockerfile
# Build stage
FROM node:18-alpine AS build

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy source code
COPY . .

# Build TypeScript (if using TypeScript)
RUN npm run build

# Production stage
FROM node:18-alpine

WORKDIR /app

# Create a non-root user
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001

# Copy dependencies and built application
COPY --from=build --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=build --chown=nodejs:nodejs /app/dist ./dist
COPY --from=build --chown=nodejs:nodejs /app/package*.json ./

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 8081

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8081/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

ENV NODE_ENV=production
ENV PORT=8081

CMD ["node", "dist/main.js"]
```

## Python FastAPI (Alternative API Implementation)

**File: `Dockerfile.python`**

```dockerfile
# Build stage
FROM python:3.11-slim AS builder

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

# Create non-root user
RUN useradd -m -u 1001 appuser && chown -R appuser /app
USER appuser

# Copy Python dependencies from builder
COPY --from=builder --chown=appuser /root/.local /home/appuser/.local

# Copy application code
COPY --chown=appuser . .

# Update PATH
ENV PATH=/home/appuser/.local/bin:$PATH

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# Run with uvicorn
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

## Go API (Alternative High-Performance API)

**File: `Dockerfile.go`**

```dockerfile
# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# Runtime stage
FROM alpine:latest

WORKDIR /app

# Install ca-certificates for HTTPS
RUN apk --no-cache add ca-certificates

# Create non-root user
RUN addgroup -g 1001 appgroup && adduser -D -u 1001 -G appgroup appuser

# Copy binary from builder
COPY --from=builder --chown=appuser:appgroup /app/main .

USER appuser

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["./main"]
```

## .dockerignore

Create a `.dockerignore` file in each application directory:

```
# Node.js
node_modules
npm-debug.log
.env
.env.local

# .NET
bin
obj
*.user
*.suo
*.cache
.vs

# Python
__pycache__
*.pyc
*.pyo
*.pyd
.Python
env
venv
pip-log.txt

# General
.git
.gitignore
README.md
.vscode
.idea
*.md
.DS_Store
Thumbs.db
```

## Build Commands Reference

### Build Locally
```bash
# Angular
docker build -f Dockerfile.angular -t angular-frontend:latest .

# .NET
docker build -f Dockerfile.dotnet -t workflow-service:latest .

# Node.js
docker build -f Dockerfile.nodejs -t frontend-api-1:latest .
```

### Build and Push to ACR
```bash
# Get ACR name
ACR_NAME="yourregistry.azurecr.io"

# Login to ACR
az acr login --name yourregistry

# Build and push
az acr build \
  --registry yourregistry \
  --image angular-frontend:latest \
  --image angular-frontend:v1.0.0 \
  --file Dockerfile.angular \
  .
```

### Multi-stage Build Benefits
- **Smaller images**: Only production dependencies and compiled code in final image
- **Security**: Build tools not included in runtime image
- **Faster deployments**: Smaller images pull faster
- **Non-root user**: Enhanced security by not running as root

## Best Practices

1. **Use specific base image tags** (not `latest`)
2. **Multi-stage builds** to reduce image size
3. **Run as non-root user** for security
4. **Include health checks** for Kubernetes liveness/readiness probes
5. **Layer caching**: Copy package files before source code
6. **Environment variables**: Use for configuration
7. **.dockerignore**: Exclude unnecessary files
8. **Image tagging**: Use semantic versioning + commit SHA
