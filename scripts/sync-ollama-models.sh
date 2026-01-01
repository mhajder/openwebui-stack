#!/bin/bash
# =============================================================================
# Sync Ollama Models with LiteLLM
# =============================================================================
# This script syncs models from Ollama to LiteLLM Proxy
# It prompts the user for configuration details and registers each model

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Ollama to LiteLLM Model Sync Script${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Function to prompt for input
prompt_input() {
    local prompt="$1"
    local default="$2"
    local input

    if [ -n "$default" ]; then
        read -rp "$(echo -e "${YELLOW}${prompt}${NC} [${GREEN}${default}${NC}]: ")" input
        echo "${input:-$default}"
    else
        read -rp "$(echo -e "${YELLOW}${prompt}${NC}: ")" input
        echo "$input"
    fi
}

# Collect user inputs
echo -e "${BLUE}Please provide the following configuration:${NC}"
echo ""

OLLAMA_PUBLIC_URL=$(prompt_input "Ollama Public URL (accessible from your environment)" "http://localhost:11434")
OLLAMA_INTERNAL_URL=$(prompt_input "Ollama Internal URL (for LiteLLM, can be same as public)" "$OLLAMA_PUBLIC_URL")
LITELLM_URL=$(prompt_input "LiteLLM API URL" "http://localhost:4000")
LITELLM_MASTER_KEY=$(prompt_input "LiteLLM Master Key" "")

if [ -z "$LITELLM_MASTER_KEY" ]; then
    echo -e "${RED}Error: LiteLLM Master Key cannot be empty${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e "  Ollama Public URL: ${GREEN}${OLLAMA_PUBLIC_URL}${NC}"
echo -e "  Ollama Internal URL: ${GREEN}${OLLAMA_INTERNAL_URL}${NC}"
echo -e "  LiteLLM URL: ${GREEN}${LITELLM_URL}${NC}"
echo -e "  LiteLLM Key: ${GREEN}${LITELLM_MASTER_KEY:0:10}...${NC}"
echo ""

read -rp "Continue with these settings? (y/n): " -n 1 REPLY
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Fetching models from Ollama...${NC}"

# Fetch models from Ollama
if ! RESPONSE=$(curl -k -s -X GET "${OLLAMA_PUBLIC_URL}/api/tags"); then
    echo -e "${RED}Error: Failed to connect to Ollama at ${OLLAMA_PUBLIC_URL}${NC}"
    exit 1
fi

# Check if response contains models
if ! echo "$RESPONSE" | grep -q "models"; then
    echo -e "${RED}Error: No models found in Ollama response${NC}"
    echo "Response: $RESPONSE"
    exit 1
fi

# Extract model names using jq if available, otherwise use grep/sed
if command -v jq &>/dev/null; then
    MODELS=$(echo "$RESPONSE" | jq -r '.models[].name')
else
    # Fallback to grep/sed parsing
    MODELS=$(echo "$RESPONSE" | grep -oP '"name"\s*:\s*"\K[^"]+')
fi

if [ -z "$MODELS" ]; then
    echo -e "${RED}Error: Could not parse models from Ollama${NC}"
    exit 1
fi

MODEL_COUNT=$(echo "$MODELS" | wc -l)
echo -e "${GREEN}Found ${MODEL_COUNT} models in Ollama${NC}"
echo ""

# Convert to array for counting
mapfile -t MODELS_ARRAY <<<"$MODELS"

# Fetch existing models from LiteLLM
echo -e "${BLUE}Fetching models from LiteLLM...${NC}"

if LITELLM_RESPONSE=$(curl -k -s -X GET \
    -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
    "${LITELLM_URL}/models" 2>&1); then

    # Extract model names from LiteLLM response
    if command -v jq &>/dev/null; then
        EXISTING_MODELS=$(echo "$LITELLM_RESPONSE" | jq -r '.data[].id' 2>/dev/null | sort)
    else
        EXISTING_MODELS=$(echo "$LITELLM_RESPONSE" | grep -oP '"id"\s*:\s*"\K[^"]+' | sort)
    fi

    echo -e "${GREEN}Found $(echo "$EXISTING_MODELS" | grep -c . || echo 0) models in LiteLLM${NC}"
else
    echo -e "${YELLOW}Warning: Could not fetch existing models from LiteLLM${NC}"
    EXISTING_MODELS=""
fi

echo ""

# Track statistics
SUCCESSFUL=0
FAILED=0
SKIPPED=0

# Register each model with LiteLLM
for model_name in "${MODELS_ARRAY[@]}"; do
    if [ -z "$model_name" ]; then
        continue
    fi

    # Check if model already exists in LiteLLM
    full_model_name="ollama/${model_name}"
    if echo "$EXISTING_MODELS" | grep -q "^${full_model_name}$"; then
        echo -e "Skipping ${YELLOW}${model_name}${NC}... ${YELLOW}Already exists${NC}"
        ((SKIPPED++))
        continue
    fi

    echo -ne "Syncing ${YELLOW}${model_name}${NC}... "

    # Create JSON payload
    PAYLOAD=$(
        cat <<EOF
{
    "model_name": "ollama/${model_name}",
    "litellm_params": {
        "model": "ollama/${model_name}",
        "api_base": "${OLLAMA_INTERNAL_URL}"
    }
}
EOF
    )

    # Send to LiteLLM
    if RESPONSE=$(curl -k -s -X POST \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "${LITELLM_URL}/model/new" 2>&1); then

        # Check response (LiteLLM returns 200 on success or various status codes)
        if echo "$RESPONSE" | grep -q '"status":\s*"success"\|"model_name"'; then
            echo -e "${GREEN}✓ Success${NC}"
            ((SUCCESSFUL++))
        elif echo "$RESPONSE" | grep -q '"error"'; then
            echo -e "${RED}✗ Failed${NC}"
            echo -e "  ${RED}Response: $(echo "$RESPONSE" | head -c 100)${NC}"
            ((FAILED++))
        else
            # If no explicit error field, assume success
            echo -e "${GREEN}✓ Added${NC}"
            ((SUCCESSFUL++))
        fi
    else
        echo -e "${RED}✗ Request Failed${NC}"
        echo -e "  ${RED}Error: ${RESPONSE}${NC}"
        ((FAILED++))
    fi
done

echo ""
echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}Sync Complete${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "  ${GREEN}Successful: ${SUCCESSFUL}${NC}"
echo -e "  ${YELLOW}Skipped: ${SKIPPED}${NC}"
echo -e "  ${RED}Failed: ${FAILED}${NC}"
echo -e "  Total Found: ${MODEL_COUNT}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All models processed successfully!${NC}"
    exit 0
else
    echo -e "${YELLOW}Some models failed to sync. Check the errors above.${NC}"
    exit 1
fi
