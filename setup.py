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
    # "https://github.com/jrdurandt/joltc-odin/archive/refs/heads/master.zip"
    "https://github.com/jrdurandt/joltc-odin/archive/refs/heads/feat/joltc-fork.zip"
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

    if not os.path.exists("jolt-odin"):
        do_update_jolt_odin = True

    if do_update_jolt_odin:
        print("Downloading joltc-odin...")
        urllib.request.urlretrieve(JOLT_ODIN_ZIP_URL, "joltc-odin.zip")

        print("Extracting joltc-odin...")
        with zipfile.ZipFile("joltc-odin.zip", "r") as zip_ref:
            zip_ref.extractall(owd)
            shutil.move("joltc-odin-feat-joltc-fork", "joltc-odin")

    do_build_joltc = args.build_joltc
    if IS_LINUX:
        if not os.path.exists("libjoltc.so"):
            do_build_joltc = True
    elif IS_WINDOWS:
        if not os.path.exists("joltc.dll") and not os.path.exists("joltc.lib"):
            do_build_joltc = True

    if do_build_joltc:
        print("Building joltc-odin...")
        os.chdir("joltc-odin")
        subprocess.run([sys.executable, "build.py", "-build-lib"], check=True)

        if IS_WINDOWS:
            shutil.copy("joltc.dll", owd)
            shutil.copy("joltc.lib", owd)
        elif IS_LINUX:
            shutil.copy("libjoltc.so", owd)

    # Clean up
    print("Cleaning up...")
    os.chdir(owd)
    os.remove("joltc-odin.zip")


main()
