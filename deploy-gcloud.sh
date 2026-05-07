#!/bin/bash
# ============================================================
#  Yörünge Muhafızı — Google Cloud Run Deployment (Debian/Linux)
#  Maliyet: ~$0/gün (Free Tier) veya ~$1-2/gün (min-instances:1)
# ============================================================
# Ön koşul:
#   sudo apt install -y google-cloud-cli docker.io
#   gcloud auth login
# Çalıştırmak için:
#   chmod +x deploy-gcloud.sh
#   ./deploy-gcloud.sh
# Sadece build + push (Cloud Run yok; imajı sonra GCE VM'de pull ile çalıştırmak için):
#   SKIP_DEPLOY=1 ./deploy-gcloud.sh
# ============================================================

set -e  # hata olursa dur

# ── YAPILANDIRMA (değiştir) ──────────────────────────────────
PROJECT_ID=""                        # boşsa otomatik alır
REGION="us-central1"                 # Iowa (Free Tier için en uygun)
SERVICE_NAME="yorunge-muhafizi"
IMAGE_NAME="yorunge-muhafizi"
IMAGE_TAG="latest"
REPO_NAME="yorunge-repo"
# ─────────────────────────────────────────────────────────────

# Renkli çıktı
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;37m'
NC='\033[0m'

echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Yörünge Muhafızı — Google Cloud Run Deployment${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ── 1. gcloud kontrolü ──────────────────────────────────────
echo -e "${CYAN}=== 1. gcloud kontrol ediliyor ===${NC}"
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}gcloud bulunamadı! Kurulum için:${NC}"
    echo "  sudo apt-get install -y apt-transport-https ca-certificates gnupg"
    echo "  echo 'deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main' | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list"
    echo "  curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -"
    echo "  sudo apt-get update && sudo apt-get install -y google-cloud-cli"
    exit 1
fi
gcloud --version | head -1

# ── 2. Docker kontrolü ──────────────────────────────────────
echo ""
echo -e "${CYAN}=== 2. Docker kontrol ediliyor ===${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker bulunamadı! Kurulum:${NC}"
    echo "  sudo apt-get install -y docker.io"
    echo "  sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi
docker --version

# ── 3. Giriş kontrolü ───────────────────────────────────────
echo ""
echo -e "${CYAN}=== 3. Giriş kontrol ediliyor ===${NC}"
CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
if [ -z "$CURRENT_ACCOUNT" ]; then
    echo -e "${YELLOW}Giriş yapılıyor...${NC}"
    gcloud auth login
fi
echo -e "${GRAY}Aktif hesap: $CURRENT_ACCOUNT${NC}"

# Project ID otomatik al
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}Project ID bulunamadı!${NC}"
        echo "Şunu çalıştır: gcloud projects list"
        echo "Sonra PROJECT_ID değişkenini bu scriptte doldur."
        exit 1
    fi
fi
gcloud config set project "$PROJECT_ID"
echo -e "${GRAY}Project: $PROJECT_ID${NC}"

# ── 4. API'leri aktif et ─────────────────────────────────────
echo ""
echo -e "${CYAN}=== 4. Cloud Run ve Artifact Registry API'leri aktif ediliyor ===${NC}"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com --quiet

# ── 5. Artifact Registry deposu oluştur ─────────────────────
echo ""
echo -e "${CYAN}=== 5. Artifact Registry deposu oluşturuluyor ===${NC}"
gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Yörünge Muhafızı container deposu" \
    --quiet 2>/dev/null || echo -e "${GRAY}Depo zaten mevcut, devam ediliyor...${NC}"

FULL_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:$IMAGE_TAG"
echo -e "${GRAY}Image: $FULL_IMAGE${NC}"

# ── 6. Docker kimlik doğrulaması ─────────────────────────────
echo ""
echo -e "${CYAN}=== 6. Docker kimlik doğrulaması yapılıyor ===${NC}"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

# ── 7. Docker image build et ─────────────────────────────────
echo ""
echo -e "${CYAN}=== 7. Docker image build ediliyor (10-15 dakika sürebilir) ===${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
docker build --platform linux/amd64 --target runtime -t "$FULL_IMAGE" "$SCRIPT_DIR"
echo -e "${GREEN}Build tamamlandı.${NC}"

# ── 8. Image push et ─────────────────────────────────────────
echo ""
echo -e "${CYAN}=== 8. Image Artifact Registry'ye push ediliyor ===${NC}"
docker push "$FULL_IMAGE"
echo -e "${GREEN}Push tamamlandı.${NC}"

if [[ "${SKIP_DEPLOY:-}" != "1" ]]; then
  # ── 9. Cloud Run'a deploy et ─────────────────────────────────
  echo ""
  echo -e "${CYAN}=== 9. Google Cloud Run'a deploy ediliyor ===${NC}"
  # Next.js `server.js` Cloud Run'un verdiği PORT üzerinden dinler (varsayılan 8080).
  # Yayın URL'si yine https://... — tarayıcıda 3000/8081 görünmez; yalnızca konteyner içi port.
  gcloud run deploy "$SERVICE_NAME" \
      --image="$FULL_IMAGE" \
      --platform=managed \
      --region="$REGION" \
      --port=8080 \
      --memory=2Gi \
      --cpu=1 \
      --timeout=3600 \
      --min-instances=0 \
      --max-instances=1 \
      --allow-unauthenticated \
      --quiet

  # ── 10. Public URL al ────────────────────────────────────────
  echo ""
  echo -e "${CYAN}=== 10. Public URL alınıyor ===${NC}"
  SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
      --platform=managed \
      --region="$REGION" \
      --format="value(status.url)" 2>/dev/null)

  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  YÖRÜNGE MUHAFIZI — DEPLOYMENT TAMAMLANDI!${NC}"
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${YELLOW}  Dashboard URL : $SERVICE_URL${NC}"
  echo -e "${GRAY}  Project       : $PROJECT_ID${NC}"
  echo -e "${GRAY}  Region        : $REGION${NC}"
  echo -e "${GRAY}  Image         : $FULL_IMAGE${NC}"
  echo -e "${GREEN}============================================================${NC}"
  echo ""
  echo -e "${GRAY}Kapatmak için       : ./teardown-gcloud.sh${NC}"
  echo -e "${GRAY}Logları görmek için : gcloud run services logs read $SERVICE_NAME --region=$REGION${NC}"
else
  echo ""
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${GREEN}  BUILD + PUSH TAMAMLANDI (SKIP_DEPLOY=1)${NC}"
  echo -e "${GREEN}============================================================${NC}"
  echo -e "${YELLOW}  Image : $FULL_IMAGE${NC}"
  echo -e "${GRAY}  Cloud Run için SKIP_DEPLOY kullanmadan ./deploy-gcloud.sh çalıştırın.${NC}"
  echo -e "${GREEN}============================================================${NC}"
fi
