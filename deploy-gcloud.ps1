param(
    # Yalnızca Docker build + Artifact Registry push; Cloud Run güncellenmez
    [switch]$SkipDeploy
)

# ============================================================
#  Yörünge Muhafızı — Google Cloud Run Deployment Scripti
#  Maliyet: ~$0/gün (Free Tier) veya ~$1-2/gün (min-instances:1)
# ============================================================
# Ön koşul: Google Cloud SDK kurulu olmalı
#   https://cloud.google.com/sdk/docs/install
# Çalıştırmadan önce: gcloud auth login
# Tam akış:  .\deploy-gcloud.ps1
# Sadece build + push: .\deploy-gcloud.ps1 -SkipDeploy
# ============================================================

# ── YAPILANDIRMA (değiştir) ──────────────────────────────────
$PROJECT_ID    = ""                        # BURAYA: gcloud projects list ile bul
$REGION        = "us-central1-a"               # Iowa (Free Tier için en uygun)
$SERVICE_NAME  = "yorunge-muhafizi"
$IMAGE_NAME    = "yorunge-muhafizi"
$IMAGE_TAG     = "latest"
# ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Yörünge Muhafızı — Google Cloud Run Deployment" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. gcloud kontrolü ──────────────────────────────────────
Write-Host "=== 1. gcloud kontrol ediliyor ===" -ForegroundColor Cyan
gcloud --version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -ne 0) {
    Write-Host "gcloud bulunamadı! https://cloud.google.com/sdk/docs/install adresinden kur." -ForegroundColor Red
    exit 1
}

# ── 2. Giriş ve proje ───────────────────────────────────────
Write-Host ""
Write-Host "=== 2. Giriş kontrol ediliyor ===" -ForegroundColor Cyan
$currentAccount = gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>$null
if (-not $currentAccount) {
    Write-Host "Giriş yapılıyor..." -ForegroundColor Yellow
    gcloud auth login
}
Write-Host "Aktif hesap: $currentAccount" -ForegroundColor Gray

# Project ID otomatik al (boşsa)
if (-not $PROJECT_ID) {
    $PROJECT_ID = gcloud config get-value project 2>$null
    if (-not $PROJECT_ID) {
        Write-Host "Project ID bulunamadı! Şunu çalıştır: gcloud projects list" -ForegroundColor Red
        exit 1
    }
}
gcloud config set project $PROJECT_ID
Write-Host "Project: $PROJECT_ID" -ForegroundColor Gray

# ── 3. Gerekli API'leri aktif et ────────────────────────────
Write-Host ""
Write-Host "=== 3. Cloud Run ve Artifact Registry API'leri aktif ediliyor ===" -ForegroundColor Cyan
gcloud services enable run.googleapis.com artifactregistry.googleapis.com --quiet

# ── 4. Artifact Registry deposu oluştur ─────────────────────
Write-Host ""
Write-Host "=== 4. Artifact Registry deposu oluşturuluyor ===" -ForegroundColor Cyan
$REPO_NAME = "yorunge-repo"
gcloud artifacts repositories create $REPO_NAME `
    --repository-format=docker `
    --location=$REGION `
    --description="Yörünge Muhafızı container deposu" `
    --quiet 2>$null
Write-Host "Depo: $REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME" -ForegroundColor Gray

# ── 5. Docker kimlik doğrulaması ─────────────────────────────
Write-Host ""
Write-Host "=== 5. Docker kimlik doğrulaması yapılıyor ===" -ForegroundColor Cyan
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

# ── 6. Docker image build et ─────────────────────────────────
Write-Host ""
Write-Host "=== 6. Docker image build ediliyor (10-15 dakika sürebilir) ===" -ForegroundColor Cyan
$FULL_IMAGE = "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/${IMAGE_NAME}:${IMAGE_TAG}"
Write-Host "Image: $FULL_IMAGE" -ForegroundColor Gray

docker build --target runtime -t $FULL_IMAGE .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker build başarısız! Docker Desktop açık mı?" -ForegroundColor Red
    exit 1
}

# ── 7. Image push et ─────────────────────────────────────────
Write-Host ""
Write-Host "=== 7. Image Artifact Registry'ye push ediliyor ===" -ForegroundColor Cyan
docker push $FULL_IMAGE
if ($LASTEXITCODE -ne 0) {
    Write-Host "Push başarısız!" -ForegroundColor Red
    exit 1
}

if (-not $SkipDeploy) {
    # ── 8. Cloud Run'a deploy et ─────────────────────────────────
    Write-Host ""
    Write-Host "=== 8. Google Cloud Run'a deploy ediliyor ===" -ForegroundColor Cyan
    gcloud run deploy $SERVICE_NAME `
        --image=$FULL_IMAGE `
        --platform=managed `
        --region=$REGION `
        --port=8501 `
        --memory=2Gi `
        --cpu=1 `
        --timeout=3600 `
        --min-instances=0 `
        --max-instances=1 `
        --allow-unauthenticated `
        --set-env-vars="STREAMLIT_SERVER_PORT=8501,STREAMLIT_SERVER_ADDRESS=0.0.0.0,STREAMLIT_SERVER_HEADLESS=true,STREAMLIT_BROWSER_GATHER_USAGE_STATS=false" `
        --quiet

    # ── 9. Public URL al ─────────────────────────────────────────
    Write-Host ""
    Write-Host "=== 9. Public URL alınıyor ===" -ForegroundColor Cyan
    $SERVICE_URL = gcloud run services describe $SERVICE_NAME `
        --platform=managed `
        --region=$REGION `
        --format="value(status.url)" 2>$null

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  YÖRÜNGE MUHAFIZI — DEPLOYMENT TAMAMLANDI!" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  Dashboard URL : $SERVICE_URL" -ForegroundColor Yellow
    Write-Host "  Project       : $PROJECT_ID" -ForegroundColor Gray
    Write-Host "  Region        : $REGION" -ForegroundColor Gray
    Write-Host "  Image         : $FULL_IMAGE" -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Kapatmak için: .\teardown-gcloud.ps1" -ForegroundColor Gray
    Write-Host "Logları görmek: gcloud run services logs read $SERVICE_NAME --region=$REGION" -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  BUILD + PUSH TAMAMLANDI (-SkipDeploy)" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  Image         : $FULL_IMAGE" -ForegroundColor Yellow
    Write-Host "  Cloud Run güncellemek için -SkipDeploy kullanmadan çalıştırın veya:" -ForegroundColor Gray
    Write-Host "  gcloud run deploy $SERVICE_NAME --image=$FULL_IMAGE --region=$REGION --platform=managed ..." -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Green
}
