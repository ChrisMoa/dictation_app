#!/bin/bash

# Dictation App - Linux Installation Script

echo "📦 Installing Dictation App..."
echo "This will install the app to /opt/dictation_app"
echo ""

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo:"
    echo "  sudo ./install.sh"
    exit 1
fi

# Check if release build exists
RELEASE_PATH="build/linux/x64/release/bundle"
if [ ! -d "$RELEASE_PATH" ]; then
    echo "❌ Error: Release build not found at $RELEASE_PATH"
    echo ""
    echo "Building Linux release version..."

    # Drop sudo privileges for build
    REAL_USER=$(who am i | awk '{print $1}')
    if [ -n "$REAL_USER" ]; then
        sudo -u "$REAL_USER" flutter build linux --release
    else
        # Fallback: try with SUDO_USER
        if [ -n "$SUDO_USER" ]; then
            sudo -u "$SUDO_USER" flutter build linux --release
        else
            flutter build linux --release
        fi
    fi

    if [ $? -ne 0 ]; then
        echo "❌ Build failed!"
        exit 1
    fi

    echo "✅ Build complete!"
    echo ""
fi

# Create installation directory
echo "Creating installation directory at /opt/dictation_app..."
mkdir -p /opt/dictation_app

# Copy application files
echo "Copying application files..."
cp -r build/linux/x64/release/bundle/* /opt/dictation_app/

# Install icon
echo "Installing application icon..."
mkdir -p /usr/share/icons/hicolor/256x256/apps
cp assets/app_logo.png /usr/share/icons/hicolor/256x256/apps/dictation_app.png

# Install desktop entry
echo "Installing desktop entry..."
cp dictation_app.desktop /usr/share/applications/

# Make executable
echo "Setting executable permissions..."
chmod +x /opt/dictation_app/dictation_app

# Update icon cache
echo "Updating icon cache..."
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

# Update desktop database
echo "Updating desktop database..."
update-desktop-database /usr/share/applications/ 2>/dev/null || true

# Update mime database
echo "Updating mime database..."
update-mime-database /usr/share/mime 2>/dev/null || true

echo ""
echo "✅ Installation complete!"
echo ""
echo "Icon installed to: /usr/share/icons/hicolor/256x256/apps/dictation_app.png"
echo "Desktop entry: /usr/share/applications/dictation_app.desktop"
echo ""
echo "You can now launch 'Dictation App' from your application menu."
echo "Or run it from terminal: /opt/dictation_app/dictation_app"
echo ""
echo "Note: You may need to log out and back in to see the icon."
