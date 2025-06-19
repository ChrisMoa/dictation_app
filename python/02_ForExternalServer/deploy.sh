#!/bin/bash
# deploy.sh - Complete automated deployment with interactive configuration

set -e

echo "🚀 German GEC Server - Interactive Deployment"
echo "=============================================="

# Interactive configuration
echo ""
echo "📝 Please provide the following information:"
echo ""

# Get server configuration
read -p "🖥️  Server IP/Hostname: " SERVER_HOST
read -p "👤 SSH Username: " SERVER_USER
read -s -p "🔐 SSH Password: " SERVER_PASSWORD
echo
read -p "🌐 Domain name (or press Enter for IP): " DOMAIN_INPUT
read -p "📁 Path to german_gec_mt5 model (default: ./german_gec_mt5): " MODEL_PATH

# Set defaults
if [[ -z "$DOMAIN_INPUT" ]]; then
    DOMAIN_NAME="$SERVER_HOST"
else
    DOMAIN_NAME="$DOMAIN_INPUT"
fi

if [[ -z "$MODEL_PATH" ]]; then
    MODEL_PATH="./german_gec_mt5"
fi

# Fixed configuration
CONTAINER_NAME="gec-server"
CONTAINER_PORT="8001"
EXTERNAL_PORT="80"
USE_REVERSE_PROXY="true"

echo ""
echo "📋 Configuration Summary:"
echo "   Server: $SERVER_USER@$SERVER_HOST"
echo "   Domain: $DOMAIN_NAME"
echo "   Model Path: $MODEL_PATH"
echo "   Architecture: Internet:80 → Nginx → Docker:$CONTAINER_PORT → App:8000"
echo ""
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

# Test SSH connection
echo "🔐 Testing SSH connection..."

# Check if sshpass is available
if ! command -v sshpass &> /dev/null; then
    echo "📦 Installing sshpass for password authentication..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y sshpass
    elif command -v yum &> /dev/null; then
        sudo yum install -y sshpass
    elif command -v brew &> /dev/null; then
        brew install hudochenkov/sshpass/sshpass
    else
        echo "❌ Please install sshpass manually: sudo apt install sshpass"
        exit 1
    fi
fi

# Test SSH connection with password
if ! sshpass -p "$SERVER_PASSWORD" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no $SERVER_USER@$SERVER_HOST 'echo "SSH connection successful"' 2>/dev/null; then
    echo "❌ SSH connection failed!"
    echo "💡 Please check:"
    echo "   - Server IP/hostname is correct"
    echo "   - Username is correct"
    echo "   - Password is correct"
    echo "   - SSH service is running on server"
    exit 1
fi
echo "✅ SSH connection verified"

# Check required files exist locally
echo "📋 Checking local files..."
required_files=("gec_server_pytorch.py" "requirements_server.txt" "Dockerfile")

for file in "${required_files[@]}"; do
    if [[ ! -e "$file" ]]; then
        echo "❌ Missing file: $file"
        exit 1
    fi
done

# Check model directory
if [[ ! -d "$MODEL_PATH" ]]; then
    echo "❌ Model directory not found: $MODEL_PATH"
    echo "💡 Please check the path to your german_gec_mt5 model"
    exit 1
fi

echo "✅ All required files found"
echo "✅ Model directory found: $MODEL_PATH"

# Create deployment package
echo "📦 Creating deployment package..."
tar -czf gec-deployment.tar.gz \
    Dockerfile \
    gec_server_pytorch.py \
    requirements_server.txt \
    german_gec_mt5/

echo "📤 Uploading files to server ($SERVER_HOST)..."
scp gec-deployment.tar.gz $SERVER_USER@$SERVER_HOST:~/

echo "🔧 Building and starting container on server..."
ssh $SERVER_USER@$SERVER_HOST << 'REMOTE_COMMANDS'
    echo "📦 Extracting files..."
    tar -xzf gec-deployment.tar.gz
    
    echo "🛑 Stopping old container if exists..."
    docker stop gec-server 2>/dev/null || true
    docker rm gec-server 2>/dev/null || true
    
    echo "🔨 Building Docker image..."
    docker build -t german-gec-server:latest .
    
    echo "🚀 Starting new container..."
    docker run -d \
        --name gec-server \
        --restart unless-stopped \
        -p $CONTAINER_PORT:8000 \
        --memory=4g \
        --cpus=2 \
        german-gec-server:latest
    
    echo "🧹 Cleaning up..."
    rm gec-deployment.tar.gz
    
    echo "📊 Container status:"
    docker ps | grep gec-server
REMOTE_COMMANDS

# Test deployment
echo "🧪 Testing deployment (waiting 15 seconds for startup)..."
sleep 15

# Determine test URL based on reverse proxy usage
if [[ "$USE_REVERSE_PROXY" == "true" ]]; then
    TEST_URL="http://$SERVER_HOST:$EXTERNAL_PORT"
    echo "🔗 Testing via reverse proxy: $TEST_URL"
else
    TEST_URL="http://$SERVER_HOST:$CONTAINER_PORT"
    echo "🔗 Testing direct access: $TEST_URL"
fi

if curl -f -s $TEST_URL/api/v1/health > /dev/null; then
    echo "✅ Health check passed!"
    
    # Test correction API
    echo "🧪 Testing correction..."
    response=$(curl -s -X POST "$TEST_URL/api/v1/correct" \
         -H "Content-Type: application/json" \
         -d '{"text": "Das ist ein test satz."}' | head -c 200)
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Correction API working!"
        echo "📝 Sample response: $response..."
    fi
else
    echo "❌ Health check failed!"
    echo "📝 Checking server logs..."
    ssh $SERVER_USER@$SERVER_HOST "docker logs --tail 20 gec-server"
    exit 1
fi

# Cleanup local files
rm gec-deployment.tar.gz

echo ""
echo "🎉 Deployment completed successfully!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$USE_REVERSE_PROXY" == "true" ]]; then
    echo "🌐 API URL: http://$SERVER_HOST:$EXTERNAL_PORT"
    echo "📊 Health:  http://$SERVER_HOST:$EXTERNAL_PORT/api/v1/health"
    echo "🔄 Reverse Proxy → Container Port $CONTAINER_PORT"
else
    echo "🌐 API URL: http://$SERVER_HOST:$CONTAINER_PORT"
    echo "📊 Health:  http://$SERVER_HOST:$CONTAINER_PORT/api/v1/health"
    echo "🔗 Direct access to Container"
fi
echo "🔧 Logs:    ssh $SERVER_USER@$SERVER_HOST 'docker logs -f gec-server'"
echo "🛑 Stop:    ssh $SERVER_USER@$SERVER_HOST 'docker stop gec-server'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"