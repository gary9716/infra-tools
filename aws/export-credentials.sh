#!/bin/bash

# 設置 SSO 憑證的 profile
SSO_PROFILE=${1}

echo "SSO_PROFILE: $SSO_PROFILE"

# 獲取臨時憑證
CREDENTIALS=$(aws configure export-credentials --profile $SSO_PROFILE)

# 檢查上一個命令是否成功執行
if [ $? -ne 0 ]; then
    echo "錯誤: 無法獲取憑證。請確保您已登錄SSO，且提供的SSO profile是有效的。"
    return 1
fi

# 從 JSON 中提取值
ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
SECRET_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# 設置環境變數
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
export AWS_SESSION_TOKEN=$SESSION_TOKEN

echo "$SSO_PROFILE 環境變數已設置。"

# 驗證憑證是否已經被設置
echo "Verifying $SSO_PROFILE credentials..."
echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:5}..."
echo "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:5}..."
echo "AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:0:5}..."
