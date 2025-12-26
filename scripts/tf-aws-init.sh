#!/bin/bash

# --- 設定變數 ---
# 請替換成你想要的 S3 Bucket 名稱 (必須是全球唯一)
if [ -z "$1" ]; then
  echo "錯誤：請提供 S3 Bucket 名稱作為第一個參數。"
  echo "用法：$0 <S3_BUCKET_NAME> <AWS_PROFILE>"
  exit 1
fi

if [ -z "$2" ]; then
  echo "錯誤：請提供 AWS Profile 作為第二個參數。"
  echo "用法：$0 <S3_BUCKET_NAME> <AWS_PROFILE>"
  exit 1
fi

S3_BUCKET_NAME="$1"
AWS_PROFILE="$2"

# 請替換成你想要的 DynamoDB 表格名稱
DYNAMODB_TABLE_NAME="terraform-lock-table"
# 請替換成你的 AWS 區域 (例如：ap-northeast-1, us-east-1)
AWS_REGION="ap-northeast-1" # 建議使用你主要部署資源的區域

# --- 提示使用者確認 ---
echo "--- AWS Terraform Backend 設定腳本 ---"
echo "即將在區域: ${AWS_REGION} 建立以下資源:"
echo "S3 Bucket 名稱: ${S3_BUCKET_NAME}"
echo "DynamoDB Table 名稱: ${DYNAMODB_TABLE_NAME}"
echo "AWS Profile: ${AWS_PROFILE}"
echo ""
read -p "確定要繼續嗎? (y/N): " confirm

if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo "操作已取消。"
    exit 0
fi

echo "--- 正在建立 S3 Bucket ---"
# 先檢查 S3 Bucket 是否已存在
if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" --profile "${AWS_PROFILE}" 2>/dev/null; then
  echo "S3 Bucket '${S3_BUCKET_NAME}' 已存在，略過建立。"
else
  if aws s3api create-bucket --bucket "${S3_BUCKET_NAME}" --region "${AWS_REGION}" --create-bucket-configuration LocationConstraint="${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null; then
    echo "S3 Bucket '${S3_BUCKET_NAME}' 建立成功。"
  else
    echo "S3 Bucket '${S3_BUCKET_NAME}' 建立失敗，請檢查權限或名稱是否已被使用。"
    exit 1
  fi
fi

# 啟用 S3 Bucket 版本控制 (強烈建議，防止誤刪)
echo "--- 正在為 S3 Bucket '${S3_BUCKET_NAME}' 啟用版本控制 ---"
if aws s3api put-bucket-versioning --bucket "${S3_BUCKET_NAME}" --versioning-configuration Status=Enabled --profile "${AWS_PROFILE}"; then
  echo "S3 Bucket '${S3_BUCKET_NAME}' 版本控制已啟用。"
else
  echo "S3 Bucket '${S3_BUCKET_NAME}' 版本控制啟用失敗，請檢查權限。"
  exit 1
fi

# 啟用 S3 Bucket 預設伺服器端加密 (SSE-S3)
echo "--- 正在為 S3 Bucket '${S3_BUCKET_NAME}' 啟用預設伺服器端加密 (SSE-S3) ---"
ENCRYPTION_CONFIG='{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'
if aws s3api put-bucket-encryption --bucket "${S3_BUCKET_NAME}" --server-side-encryption-configuration "$ENCRYPTION_CONFIG" --profile "${AWS_PROFILE}"; then
  echo "S3 Bucket '${S3_BUCKET_NAME}' 預設伺服器端加密 (SSE-S3) 已啟用。"
else
  echo "S3 Bucket '${S3_BUCKET_NAME}' 預設伺服器端加密啟用失敗，請檢查權限。"
  exit 1
fi

echo "--- 正在建立 DynamoDB Table ---"
# 先檢查 DynamoDB Table 是否已存在
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE_NAME}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>/dev/null; then
  echo "DynamoDB Table '${DYNAMODB_TABLE_NAME}' 已存在，略過建立。"
else
  if aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" 2>/dev/null; then
    echo "DynamoDB Table '${DYNAMODB_TABLE_NAME}' 建立成功。"
  else
    echo "DynamoDB Table '${DYNAMODB_TABLE_NAME}' 建立失敗，請檢查權限或名稱是否已被使用。"
    exit 1
  fi
fi

echo "--- 所有資源已成功建立或已存在！ ---"
echo "你現在可以在你的 Terraform 配置中使用以下設定:"
echo "--------------------------------------------------"
echo "terraform {"
echo "  backend \"s3\" {"
echo "    bucket         = \"${S3_BUCKET_NAME}\""
echo "    key            = \"terraform.tfstate\" # 你的狀態檔路徑，可自訂"
echo "    region         = \"${AWS_REGION}\""
echo "    encrypt        = true"
echo "    dynamodb_table = \"${DYNAMODB_TABLE_NAME}\""
echo "  }"
echo "}"
echo "--------------------------------------------------"
echo "請記得將 'key' 路徑設定為每個 Terraform 專案或環境獨特的路徑。"
echo "例如：'dev/your-app/terraform.tfstate' 或 'prod/another-app/terraform.tfstate'"
