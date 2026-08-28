"""
Force-kill any wedged flutter/dart/java/gradle processes.
Bypasses PowerShell entirely (uses psutil via ctypes on Windows).
Writes outcome to a temp file.
"""
import os
import subprocess
import sys
import time

OUT = os.path.join(os.environ.get("TEMP", "C:\\Temp"), "_p6_kill.txt")
PROCS = ["flutter.exe", "dart.exe", "java.exe", "gradle.exe", "kotlinc.exe"]

def try_psutil():
    try:
        import psutil  # noqa
        for n in PROCS:
            for p in psutil.process_iter(attrs=["name"]):
                if p.info["name"] and p.info["name"].lower() == n.lower():
                    try:
                        p.kill()
                    except Exception as e:
                        pass
        return True
    except Exception:
        return False

def try_taskkill():
    for n in PROCS:
        subprocess.run(["taskkill", "/IM", n, "/F", "/T"],
                       capture_output=True, text=True, timeout=10)

lines = [f"start={time.strftime('%H:%M:%S')}"]
lines.append("psutil_available=" + str(try_psutil()))
try_taskkill()
lines.append(f"end={time.strftime('%H:%M:%S')}")

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print("written:", OUT)