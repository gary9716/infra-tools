#!/bin/bash
# 檢查 SSO profile 是否存在且有效

# 檢查並執行 SSO 登錄
check_and_login_sso() {
    local sso_profile=$1
    
    # 檢查 SSO 登錄狀態
    aws sts get-caller-identity --profile "$sso_profile" 2>&1
    if [ $? -ne 0 ]; then
        echo "需要 SSO 登錄..."
        aws sso login --profile "$sso_profile" 2>&1
        if [ $? -ne 0 ]; then
            echo "SSO 登錄失敗"
            return 1
        fi
        echo "SSO 登錄成功"
    else
        echo "SSO 已登錄"
    fi
    return 0
}

SSO_PROFILE=${1}

echo "使用SSO profile '$SSO_PROFILE' 獲取憑證"

# 執行 SSO 登錄
check_and_login_sso "$SSO_PROFILE" || { echo "SSO 登錄失敗，退出腳本"; return 1; }

# 獲取臨時憑證
CREDENTIALS=$(aws configure export-credentials --profile $SSO_PROFILE)

# 檢查上一個命令是否成功執行
if [ $? -ne 0 ]; then
    echo "錯誤: 無法獲取憑證。請確保您已登錄SSO，且提供的SSO profile是有效的。"
    return 1
fi
