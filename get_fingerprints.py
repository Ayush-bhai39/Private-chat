import os
import subprocess
import re

def find_keytool():
    # Try running directly
    try:
        subprocess.run(["keytool", "-help"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return "keytool"
    except FileNotFoundError:
        pass

    # Search common java home paths or android studio jdk paths
    possible_paths = [
        r"C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe",
        r"C:\Program Files\Android\Android Studio\jre\bin\keytool.exe",
        r"C:\Program Files\Java\jdk-17\bin\keytool.exe",
        r"C:\Program Files\Java\jdk-21\bin\keytool.exe",
        r"C:\Program Files\Java\jdk-11\bin\keytool.exe",
    ]
    for path in possible_paths:
        if os.path.exists(path):
            return path
            
    # Check JAVA_HOME
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        path = os.path.join(java_home, "bin", "keytool.exe")
        if os.path.exists(path):
            return path

    return "keytool" # Fallback

def get_fingerprints(keystore_path, alias, storepass):
    keytool = find_keytool()
    print(f"\n--- Checking Keystore: {keystore_path} ---")
    if not os.path.exists(keystore_path):
        print(f"Error: Keystore file not found at {keystore_path}")
        return
        
    cmd = [
        keytool,
        "-list",
        "-v",
        "-keystore", keystore_path,
        "-alias", alias,
        "-storepass", storepass
    ]
    
    try:
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='ignore')
        if result.returncode != 0:
            print(f"Error running keytool: {result.stderr}")
            return
            
        output = result.stdout
        sha1 = re.search(r"SHA1:\s*([0-9A-Fa-f:]+)", output)
        sha256 = re.search(r"SHA256:\s*([0-9A-Fa-f:]+)", output)
        
        if sha1:
            print(f"SHA-1  : {sha1.group(1)}")
        if sha256:
            print(f"SHA-256: {sha256.group(1)}")
            
    except Exception as e:
        print(f"Execution failed: {e}")

# Get release signing fingerprints
release_keystore = r"E:\secure_chat\android\app\key.jks"
get_fingerprints(release_keystore, "secure_chat_alias", "secure_chat_keypass")

# Get debug signing fingerprints (standard Android location)
user_profile = os.environ.get("USERPROFILE", "")
debug_keystore = os.path.join(user_profile, ".android", "debug.keystore")
get_fingerprints(debug_keystore, "androiddebugkey", "android")
