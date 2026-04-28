#!/bin/bash
set -e

JAVA_HOME="${JAVA_HOME:-/home/umace/jdk/jdk-25}"
JAVAFX_HOME="/usr/share/openjfx/lib"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$PROJECT_DIR/src"
BUILD_DIR="$PROJECT_DIR/build"
GUI_MAIN="com.jclaw.ui.JClawApp"
CLI_MAIN="com.jclaw.Launcher"

JFX_MODULES="javafx.base,javafx.controls,javafx.fxml,javafx.graphics"
JFX_JARS=$(echo "$JAVAFX_HOME"/javafx.*.jar | tr ' ' ':')

copy_resources() {
    mkdir -p "$BUILD_DIR/com/jclaw/resources"
    cp "$SRC_DIR/com/jclaw/resources/"*.fxml "$BUILD_DIR/com/jclaw/resources/" 2>/dev/null || true
    cp "$SRC_DIR/com/jclaw/resources/"*.css "$BUILD_DIR/com/jclaw/resources/" 2>/dev/null || true
}

create_launcher() {
    local output="$1"
    cat > "$output" << 'LAUNCHEREOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export JCLAW_HOME="$DIR"
JFX_JARS=$(echo /usr/share/openjfx/lib/javafx.*.jar 2>/dev/null | tr ' ' ':')
if [ -z "$JFX_JARS" ] || [ ! -f "$(echo "$JFX_JARS" | cut -d: -f1)" ]; then
    JFX_JARS=""
fi

if [ -f "$DIR/J-Claw.jar" ]; then
    java -Dprism.order=sw \
        -Djava.library.path=/usr/lib/x86_64-linux-gnu/jni \
        -Djavafx.gtk.ime=true \
        --enable-native-access=javafx.graphics \
        ${JFX_JARS:+--module-path "$JFX_JARS"} \
        ${JFX_JARS:+--add-modules javafx.base,javafx.controls,javafx.fxml,javafx.graphics} \
        -jar "$DIR/J-Claw.jar" "$@"
else
    java -Dprism.order=sw \
        -Djava.library.path=/usr/lib/x86_64-linux-gnu/jni \
        -Djavafx.gtk.ime=true \
        --enable-native-access=javafx.graphics \
        ${JFX_JARS:+--module-path "$JFX_JARS"} \
        ${JFX_JARS:+--add-modules javafx.base,javafx.controls,javafx.fxml,javafx.graphics} \
        -cp "$DIR/build" \
        com.jclaw.ui.JClawApp "$@"
fi
LAUNCHEREOF
    chmod +x "$output"
}

cross_build_app_image() {
    local JPKG_BIN="$1"
    local JFX_MODS="$2"
    local DEST_DIR="$3"
    local INPUT_DIR="$4"
    local JFX_MOD_LIST="${JFX_MODULES//,/,}"

    echo "--- Building native app-image with jpackage ---"
    mkdir -p "$INPUT_DIR"
    cp "$DEST_DIR/J-Claw.jar" "$INPUT_DIR/"

    "$JPKG_BIN" \
        --type app-image \
        --name "J-Claw" \
        --app-version "0.4.0" \
        --description "OpenClaw Desktop Client" \
        --vendor "J-Claw" \
        --input "$INPUT_DIR" \
        --main-jar "J-Claw.jar" \
        --main-class com.jclaw.ui.JClawApp \
        --module-path "$JFX_MODS" \
        --add-modules "$JFX_MOD_LIST" \
        --dest "$DEST_DIR" \
        --java-options "-Dprism.order=sw -Djavafx.gtk.ime=true --enable-native-access=javafx.graphics" \
        --verbose 2>&1 | tail -5

    if [ -d "$DEST_DIR/J-Claw" ]; then
        cp -r "$PROJECT_DIR/runtime" "$DEST_DIR/J-Claw/runtime"
        mkdir -p "$DEST_DIR/J-Claw/config"
        cp "$PROJECT_DIR/setup-runtime.sh" "$DEST_DIR/J-Claw/"

        mkdir -p "$DEST_DIR/J-Claw/share/applications"
        cat > "$DEST_DIR/J-Claw/share/applications/j-claw.desktop" << DESKTOPEOF
[Desktop Entry]
Name=J-Claw
Comment=OpenClaw AI Assistant Desktop
Exec=/opt/j-claw/bin/J-Claw
Icon=/opt/j-claw/lib/J-Claw.png
Terminal=false
Type=Application
Categories=Utility;Office;
DESKTOPEOF

        echo "[ok] Native app-image: $DEST_DIR/J-Claw"
    fi
}

download_jre() {
    local platform="$1"
    local arch="$2"
    local dest_dir="$3"

    # Uses Adoptium API for portable JREs
    local ver="25"
    local url=""
    case "$platform/$arch" in
        windows/x64)
            url="https://api.adoptium.net/v3/binary/latest/${ver}/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk"
            ;;
        mac/x64)
            url="https://api.adoptium.net/v3/binary/latest/${ver}/ga/mac/x64/jdk/hotspot/normal/eclipse?project=jdk"
            ;;
        mac/aarch64)
            url="https://api.adoptium.net/v3/binary/latest/${ver}/ga/mac/aarch64/jdk/hotspot/normal/eclipse?project=jdk"
            ;;
        *)
            echo "Unsupported JRE target: $platform/$arch"
            return 1
            ;;
    esac

    mkdir -p "$dest_dir"
    local archive="$dest_dir/jdk-archive"
    echo "  Downloading JRE for $platform/$arch ..."
    curl -fSL --progress-bar "$url" -o "$archive" || {
        echo "  WARNING: JRE download failed for $platform/$arch"
        rm -f "$archive"
        return 1
    }

    echo "  Extracting..."
    if [[ "$archive" == *.tar.gz ]] || file "$archive" | grep -q "gzip"; then
        tar -xzf "$archive" -C "$dest_dir"
    else
        unzip -q "$archive" -d "$dest_dir"
    fi
    rm -f "$archive"

    local extracted=$(ls -d "$dest_dir"/jdk-* "$dest_dir"/jdk* "$dest_dir"/OpenJDK* 2>/dev/null | head -1)
    if [ -d "$extracted" ]; then
        mv "$extracted" "$dest_dir/jre"
    fi
    echo "  JRE ready: $(ls "$dest_dir/jre/bin/" | head -3)"
}

create_win_launcher() {
    local dir="$1"
    cat > "$dir/J-Claw.bat" << 'BATEOF'
@echo off
set DIR=%~dp0
set JCLAW_HOME=%DIR%

if exist "%DIR%jre\bin\javaw.exe" (
    "%DIR%jre\bin\javaw.exe" -Dprism.order=sw -Djavafx.gtk.ime=true --enable-native-access=javafx.graphics -jar "%DIR%J-Claw.jar" %*
) else (
    javaw -Dprism.order=sw -Djavafx.gtk.ime=true --enable-native-access=javafx.graphics -jar "%DIR%J-Claw.jar" %*
)
BATEOF

    cat > "$dir/make-installer.bat" << 'BATEOF'
@echo off
echo To create a proper .exe/.msi installer, install JDK 21+ and run:
echo   jpackage --type exe --app-image .
echo   jpackage --type msi --app-image .
echo Or use launch4j / warp-packer to wrap J-Claw.jar into .exe
pause
BATEOF
}

create_mac_launcher() {
    local dir="$1"
    cat > "$dir/J-Claw.command" << 'MACEOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export JCLAW_HOME="$DIR"
if [ -x "$DIR/jre/bin/java" ]; then
    JAVA="$DIR/jre/bin/java"
else
    JAVA="java"
fi
exec "$JAVA" -Xdock:name=J-Claw -Dprism.order=sw --enable-native-access=javafx.graphics -jar "$DIR/J-Claw.jar" "$@"
MACEOF
    chmod +x "$dir/J-Claw.command"

    cat > "$dir/make-installer.sh" << 'MACEOF'
#!/bin/bash
echo "To create a proper .dmg installer, run:"
echo "  jpackage --type dmg --app-image ."
echo ""
echo "Alternative: create-dmg (npm):"
echo "  npm install -g create-dmg"
echo "  create-dmg J-Claw.app"
MACEOF
    chmod +x "$dir/make-installer.sh"
}

cross_build_portable() {
    local platform="$1"
    local arch="$2"
    local out_name="$3"
    local platform_dir="$PROJECT_DIR/dist/cross/$out_name"
    local dist="$PROJECT_DIR/dist"

    echo ""
    echo "=== Building $out_name ==="
    rm -rf "$platform_dir"
    mkdir -p "$platform_dir"

    cp "$dist/J-Claw.jar" "$platform_dir/"
    cp -r "$dist/runtime" "$platform_dir/runtime"
    mkdir -p "$platform_dir/config"
    cp "$dist/setup-runtime.sh" "$platform_dir/"

    case "$platform" in
        windows)
            create_win_launcher "$platform_dir"
            cd "$PROJECT_DIR/dist/cross"
            zip -rq "$PROJECT_DIR/dist/$out_name.zip" "$out_name"
            cd "$PROJECT_DIR"
            echo "[ok] $out_name.zip"
            ;;
        mac)
            create_mac_launcher "$platform_dir"
            cd "$PROJECT_DIR/dist/cross"
            tar -czf "$PROJECT_DIR/dist/$out_name.tar.gz" "$out_name"
            cd "$PROJECT_DIR"
            echo "[ok] $out_name.tar.gz"
            ;;
    esac
}

case "$1" in
    clean)
        echo "Cleaning build..."
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        echo "Done."
        ;;
    runtime)
        echo "=== Setting up embedded runtime ==="
        chmod +x "$PROJECT_DIR/setup-runtime.sh"
        "$PROJECT_DIR/setup-runtime.sh"
        echo "=== Runtime ready ==="
        ;;
    gui)
        shift
        "$0" build
        echo "Starting J-Claw GUI..."
        if [ -z "$DISPLAY" ]; then
            echo "No display found, starting Xvfb..."
            Xvfb :99 -screen 0 1024x768x24 &
            XVFB_PID=$!
            export DISPLAY=:99
            trap "kill $XVFB_PID 2>/dev/null" EXIT
        fi
        export JCLAW_HOME="$PROJECT_DIR"
        java -Dprism.order=sw \
             -Djava.library.path=/usr/lib/x86_64-linux-gnu/jni \
             -Djavafx.gtk.ime=true \
             --enable-native-access=javafx.graphics \
             --module-path "$JFX_JARS" \
             --add-modules "$JFX_MODULES" \
             -cp "$BUILD_DIR" \
             "$GUI_MAIN" "$@"
        ;;
    run)
        shift
        "$0" build
        export JCLAW_HOME="$PROJECT_DIR"
        java --module-path "$JFX_JARS" \
             --add-modules "$JFX_MODULES" \
             -cp "$BUILD_DIR" \
             "$CLI_MAIN" "$@"
        ;;
    package)
        echo "=== Packaging J-Claw (portable dir) ==="
        "$0" build
        if [ ! -d "$PROJECT_DIR/runtime/node" ]; then
            echo "Runtime not found, running setup..."
            "$0" runtime
        fi

        PACKAGE_DIR="$PROJECT_DIR/package"
        rm -rf "$PACKAGE_DIR"
        mkdir -p "$PACKAGE_DIR"

        cp -r "$BUILD_DIR" "$PACKAGE_DIR/build"
        cp -r "$PROJECT_DIR/runtime" "$PACKAGE_DIR/runtime"
        mkdir -p "$PACKAGE_DIR/config"
        cp "$PROJECT_DIR/setup-runtime.sh" "$PACKAGE_DIR/"

        create_launcher "$PACKAGE_DIR/j-claw"

        echo "=== Portable package ready at $PACKAGE_DIR ==="
        ;;
    dist)
        shift
        "$0" build
        if [ ! -d "$PROJECT_DIR/runtime/node" ]; then
            "$0" runtime
        fi

        DIST_DIR="$PROJECT_DIR/dist"
        rm -rf "$DIST_DIR"
        mkdir -p "$DIST_DIR"

        echo "--- Creating J-Claw.jar ---"
        cd "$BUILD_DIR"
        jar cfe "$DIST_DIR/J-Claw.jar" com.jclaw.ui.JClawApp com/ 2>/dev/null || {
            "$JAVA_HOME"/bin/jar cfe "$DIST_DIR/J-Claw.jar" com.jclaw.ui.JClawApp com/
        }
        cd "$PROJECT_DIR"

        cp -r "$PROJECT_DIR/runtime" "$DIST_DIR/runtime"
        mkdir -p "$DIST_DIR/config"
        cp "$PROJECT_DIR/setup-runtime.sh" "$DIST_DIR/"

        create_launcher "$DIST_DIR/j-claw"

        JPKG_BIN="${JAVA_HOME}/bin/jpackage"
        if [ -x "$JPKG_BIN" ]; then
            cross_build_app_image "$JPKG_BIN" "$JAVAFX_HOME" "$DIST_DIR" "$DIST_DIR/jpkg-input"
        else
            echo "[skip] jpackage not found, app-image not built"
        fi

        echo ""
        echo "=== Dist ready at $DIST_DIR ==="
        echo "Portable: $DIST_DIR/j-claw"
        if [ -d "$DIST_DIR/J-Claw" ]; then
            echo "Native:   $DIST_DIR/J-Claw/bin/J-Claw"
        fi
        echo ""
        echo "Cross-platform: ./build.sh cross"
        ;;
    cross)
        echo "=== Cross-platform packaging ==="
        "$0" dist

        echo ""
        echo "--- Linux ---"
        cd "$PROJECT_DIR/dist"
        tar -czf "$PROJECT_DIR/dist/j-claw-linux-x64.tar.gz" J-Claw
        echo "[ok] j-claw-linux-x64.tar.gz"

        echo ""
        echo "--- Windows ---"
        cross_build_portable "windows" "x64" "j-claw-win-x64"

        echo ""
        echo "--- macOS (Intel) ---"
        cross_build_portable "mac" "x64" "j-claw-mac-x64"

        echo ""
        echo "--- macOS (Apple Silicon) ---"
        cross_build_portable "mac" "aarch64" "j-claw-mac-arm64"

        echo ""
        echo "=== All packages ready ==="
        ls -lh "$PROJECT_DIR/dist"/*.{tar.gz,zip,deb} 2>/dev/null
        echo ""
        echo "Linux:   j-claw-linux-x64.tar.gz / j-claw_*.deb"
        echo "Windows: j-claw-win-x64.zip (extract & run J-Claw.bat)"
        echo "macOS:   j-claw-mac-*.tar.gz (extract & run J-Claw.command)"
        echo ""
        echo "NOTE: macOS .dmg requires a Mac. Copy the mac archive to a Mac and run:"
        echo "  jpackage --type dmg --app-image j-claw-mac-x64/"
        echo "NOTE: Windows .exe requires Windows. Copy the win archive to Windows and run:"
        echo "  jpackage --type exe --app-image j-claw-win-x64/"
        ;;
    build|"")
        echo "Building J-Claw..."
        mkdir -p "$BUILD_DIR"
        find "$SRC_DIR" -name '*.java' > "$BUILD_DIR/sources.txt"
        javac --release 25 \
              --module-path "$JFX_JARS" \
              --add-modules "$JFX_MODULES" \
              -d "$BUILD_DIR" \
              @"$BUILD_DIR/sources.txt"
        copy_resources
        echo "Build complete. Output: $BUILD_DIR"
        ;;
esac
