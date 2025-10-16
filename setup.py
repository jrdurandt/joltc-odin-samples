#!/usr/bin/env python3

import argparse
import os
import urllib.request
import zipfile
import shutil
import platform
import subprocess
import sys

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_LINUX = SYSTEM == "Linux"
IS_OSX = SYSTEM == "Darwin"


JOLT_ODIN_ZIP_URL = (
    "https://gitlab.com/jrdurandt/jolt-odin/-/archive/latest/jolt-odin-latest.zip"
)

args_parser = argparse.ArgumentParser(
    prog="setup.py",
)

args_parser.add_argument("-update-jolt-odin", action="store_true")
args_parser.add_argument("-build-joltc", action="store_true")

args = args_parser.parse_args()


def main():
    owd = os.getcwd()

    do_update_jolt_odin = args.update_jolt_odin

    if not os.path.exists("jolt-odin-lastest"):
        do_update_jolt_odin = True

    if do_update_jolt_odin:
        print("Downloading Jolt-Odin...")
        urllib.request.urlretrieve(JOLT_ODIN_ZIP_URL, "jolt-odin.zip")

        print("Extracting Jolt-Odin...")
        with zipfile.ZipFile("jolt-odin.zip", "r") as zip_ref:
            zip_ref.extractall(owd)

    do_build_joltc = args.build_joltc
    if IS_LINUX:
        if not os.path.exists("libjoltc.so"):
            do_build_joltc = True
    elif IS_WINDOWS:
        if not os.path.exists("joltc.dll") and not os.path.exists("joltc.lib"):
            do_build_joltc = True

    if do_build_joltc:
        print("Building Jolt-Odin...")
        os.chdir("jolt-odin-latest")
        subprocess.run([sys.executable, "build.py", "-build-lib"], check=True)

        if IS_WINDOWS:
            shutil.copy("joltc.dll", owd)
            shutil.copy("joltc.lib", owd)
        elif IS_LINUX:
            shutil.copy("libjoltc.so", owd)

    # Clean up
    print("Cleaning up...")
    os.chdir(owd)
    os.remove("jolt-odin.zip")


main()
