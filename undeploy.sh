#!/bin/bash

# Resume Bot Undeploy Script
set -e

echo "🗑️  Destroying Resume Bot stacks..."

# Destroy frontend stack first (dependent on backend)
echo "Destroying frontend stack..."
npx cdk destroy ResumeBotFrontendStack --force

# Destroy backend stack
echo "Destroying backend stack..."
npx cdk destroy ResumeBotBackendStack --force

echo "✅ All stacks destroyed successfully!"