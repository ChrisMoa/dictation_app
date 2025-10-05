#!/bin/bash

# Dictation App - Android Installation Script

echo "📱 Installing Dictation App on Android..."
echo ""

# Check if APK exists
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
    echo "❌ Error: APK not found at $APK_PATH"
    echo "Please build the APK first:"
    echo "  flutter build apk --release"
    exit 1
fi

# Get connected Android device
echo "Detecting connected Android device..."
DEVICE_SERIAL=$(adb devices | grep -w "device" | awk '{print $1}' | head -n 1)

if [ -z "$DEVICE_SERIAL" ]; then
    echo "❌ Error: No Android device connected"
    echo ""
    echo "Please connect an Android device and enable USB debugging:"
    echo "  1. Connect your device via USB"
    echo "  2. Enable Developer Options"
    echo "  3. Enable USB Debugging"
    echo "  4. Accept the debugging prompt on your device"
    exit 1
fi

echo "✅ Found device: $DEVICE_SERIAL"
echo ""

# Get device info
DEVICE_MODEL=$(adb -s "$DEVICE_SERIAL" shell getprop ro.product.model | tr -d '\r')
ANDROID_VERSION=$(adb -s "$DEVICE_SERIAL" shell getprop ro.build.version.release | tr -d '\r')

echo "Device Information:"
echo "  Model: $DEVICE_MODEL"
echo "  Android Version: $ANDROID_VERSION"
echo "  Serial: $DEVICE_SERIAL"
echo ""

# Uninstall old version if exists
echo "Checking for previous installation..."
if adb -s "$DEVICE_SERIAL" shell pm list packages | grep -q "com.example.dictation_app"; then
    echo "Uninstalling previous version..."
    adb -s "$DEVICE_SERIAL" uninstall com.example.dictation_app
fi

# Install APK
echo "Installing Dictation App..."
adb -s "$DEVICE_SERIAL" install -r "$APK_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Installation complete!"
    echo ""
    echo "You can now launch 'Dictation App' on your Android device."
else
    echo ""
    echo "❌ Installation failed!"
    exit 1
fi
