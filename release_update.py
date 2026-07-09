import sys
import os
import subprocess
import re
import json
import shutil
import datetime

# 1. Check if service-account.json exists
key_path = "service-account.json"
if not os.path.exists(key_path):
    print("ERROR: 'service-account.json' not found in the project root directory.")
    print("Please download your service account private key from Firebase Console -> Project Settings -> Service Accounts,")
    print("save it in E:\\secure_chat\\ as 'service-account.json', and try again.")
    sys.exit(1)

# Install firebase-admin if not already installed
try:
    import firebase_admin
    from firebase_admin import credentials, firestore
except ImportError:
    print("Installing required python packages...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "firebase-admin"])
    import firebase_admin
    from firebase_admin import credentials, firestore

def get_git_remote_info():
    print("Retrieving Git repository information...")
    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        url = result.stdout.strip()
        
        if url.startswith("git@"):
            parts = url.split(":")[-1].replace(".git", "").split("/")
        else:
            parts = url.replace("https://github.com/", "").replace("http://github.com/", "").replace(".git", "").split("/")
        
        username = parts[0]
        repo = parts[1]

        branch_result = subprocess.run(
            ["git", "branch", "--show-current"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        branch = branch_result.stdout.strip()
        if not branch:
            branch = "main"

        return username, repo, branch
    except Exception as e:
        print("ERROR: Git remote 'origin' is not set or repository not initialized.")
        sys.exit(1)

def increment_version():
    print("Incrementing version in pubspec.yaml...")
    with open('pubspec.yaml', 'r') as f:
        content = f.read()

    match = re.search(r'version:\s*(\d+\.\d+\.\d+)\+(\d+)', content)
    if not match:
        raise Exception("Could not parse version in pubspec.yaml. Expected format: version: X.Y.Z+W")

    current_name = match.group(1)
    current_code = int(match.group(2))
    new_code = current_code + 1

    parts = current_name.split('.')
    parts[-1] = str(int(parts[-1]) + 1)
    new_name = '.'.join(parts)

    new_version_line = f"version: {new_name}+{new_code}"
    updated_content = re.sub(r'version:\s*\d+\.\d+\.\d+\+\d+', new_version_line, content)

    with open('pubspec.yaml', 'w') as f:
        f.write(updated_content)

    print(f"Version updated to {new_name}+{new_code}")

    try:
        dart_path = "lib/services/update_service.dart"
        if os.path.exists(dart_path):
            with open(dart_path, 'r', encoding='utf-8') as f:
                dart_content = f.read()
            
            dart_content = re.sub(r'static const int currentVersionCode = \d+;', f'static const int currentVersionCode = {new_code};', dart_content)
            dart_content = re.sub(r'static const String currentVersionName = "[^"]+";', f'static const String currentVersionName = "{new_name}";', dart_content)
            
            with open(dart_path, 'w', encoding='utf-8') as f:
                f.write(dart_content)
            print("Successfully updated version parameters in update_service.dart")
    except Exception as e:
        print(f"Warning: Failed to synchronize version in update_service.dart: {e}")

    return new_name, new_code

def build_apk():
    print("Building production release APK...")
    env = os.environ.copy()
    flutter_bin = r"E:\flutter\bin"
    if os.path.exists(flutter_bin):
        env["PATH"] = flutter_bin + os.pathsep + env.get("PATH", "")
        
    result = subprocess.run(
        ["flutter", "build", "apk", "--release"],
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env
    )
    print(result.stdout)
    if result.returncode != 0:
        print("ERROR: Flutter Android compilation failed.")
        sys.exit(1)
    print("Android APK build successful!")

def build_windows():
    print("Building production release Windows executable...")
    env = os.environ.copy()
    flutter_bin = r"E:\flutter\bin"
    if os.path.exists(flutter_bin):
        env["PATH"] = flutter_bin + os.pathsep + env.get("PATH", "")
    
    # Prepend project root directory to PATH so CMake can find nuget.exe locally
    env["PATH"] = r"E:\secure_chat" + os.pathsep + env.get("PATH", "")
    env["ProgramFiles(x86)"] = "C:\\Program Files (x86)"
        
    result = subprocess.run(
        ["flutter", "build", "windows", "--release"],
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env
    )
    print(result.stdout)
    if result.returncode != 0:
        print("ERROR: Flutter Windows compilation failed.")
        sys.exit(1)
    print("Windows compilation successful!")

def build_windows_installer(version_name):
    print("Creating Windows Inno Setup installer...")
    
    # Inno Setup template configuration script
    iss_template = """[Setup]
AppName=Secret Chat
AppVersion={version}
DefaultDirName={userpf}\\Secret Chat
DefaultGroupName=Secret Chat
OutputDir=E:\\secure_chat\\docs
OutputBaseFilename=secure_chat_installer
Compression=lzma
SolidCompression=yes
UninstallDisplayIcon={app}\\secure_chat.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "E:\\secure_chat\\build\\windows\\x64\\runner\\Release\\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\Secret Chat"; Filename: "{app}\\secure_chat.exe"
Name: "{autodesktop}\\Secret Chat"; Filename: "{app}\\secure_chat.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\\secure_chat.exe"; Description: "{cm:LaunchProgram,Secret Chat}"; Flags: nowait postinstall skipifsilent
"""
    iss_content = iss_template.replace("{version}", version_name)
    
    with open("installer.iss", "w", encoding="utf-8") as f:
        f.write(iss_content)
        
    iscc_path = os.path.expandvars(r"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe")
    if not os.path.exists(iscc_path):
        iscc_path = r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
        
    print(f"Running Inno Setup compiler: {iscc_path}")
    result = subprocess.run(
        [iscc_path, "installer.iss"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )
    print(result.stdout)
    
    try:
        os.remove("installer.iss")
    except Exception:
        pass
        
    if result.returncode != 0:
        print("ERROR: Inno Setup compilation failed.")
        sys.exit(1)
    print("Windows installer built and placed in 'docs/secure_chat_installer.exe'!")

def push_to_github(branch):
    print("Copying APK to project root directory...")
    src_apk = "build/app/outputs/flutter-apk/app-release.apk"
    dest_apk = "app-release.apk"
    shutil.copyfile(src_apk, dest_apk)
    print(f"APK copied to root as {dest_apk}")

    print("Pushing updates and compiled binaries to GitHub...")
    env = os.environ.copy()
    flutter_bin = r"E:\flutter\bin"
    if os.path.exists(flutter_bin):
        env["PATH"] = flutter_bin + os.pathsep + env.get("PATH", "")
        
    try:
        subprocess.run(["git", "add", "-A"], check=True, env=env)
        subprocess.run(["git", "commit", "-m", f"Release version {datetime_str()}"], check=True, env=env)
        subprocess.run(["git", "push", "origin", branch], check=True, env=env)
        print("Pushed to GitHub successfully!")
    except Exception as e:
        print(f"ERROR pushing to GitHub: {e}")
        sys.exit(1)

def datetime_str():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def upload_and_publish():
    username, repo, branch = get_git_remote_info()
    new_name, new_code = increment_version()
    
    # Compile targets for both platforms
    build_apk()
    build_windows()
    build_windows_installer(new_name)
    
    # Commit changes and upload binaries
    push_to_github(branch)

    # Construct GitHub raw direct download URL
    download_url_android = f"https://github.com/{username}/{repo}/raw/{branch}/app-release.apk"
    download_url_windows = f"https://github.com/{username}/{repo}/raw/{branch}/docs/secure_chat_installer.exe"
    
    print(f"Android Download URL: {download_url_android}")
    print(f"Windows Download URL: {download_url_windows}")

    print("Initializing Firebase Admin SDK to update Firestore...")
    cred = credentials.Certificate(key_path)
    firebase_admin.initialize_app(cred)

    db = firestore.client()
    doc_ref = db.collection("metadata").document("app_config")
    doc_ref.set({
        # Android update properties
        "latestVersionCode": new_code,
        "latestVersionName": new_name,
        "downloadUrl": download_url_android,
        "forceUpdate": True,
        
        # Windows update properties
        "latestVersionCodeWindows": new_code,
        "latestVersionNameWindows": new_name,
        "downloadUrlWindows": download_url_windows,
        "forceUpdateWindows": True
    }, merge=True)
    
    print("\n🎉 SUCCESS!")
    print(f"1. Android APK compiled and pushed to: {download_url_android}")
    print(f"2. Windows Installer compiled and pushed to: {download_url_windows}")
    print("3. Firestore config updated for both platforms. All users will now receive in-app update prompts!")

if __name__ == "__main__":
    upload_and_publish()
