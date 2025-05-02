# Copyright (C) 2025 Infineon Technologies
# SPDX-License-Identifier: Apache-2.0

import os;

base_app_src_dir = "untitled"

try:
    full_app_src_dir = os.getenv("APPLICATION_SOURCE_DIR")
    full_app_src_dir = os.path.normpath(full_app_src_dir)
    if os.path.isdir(full_app_src_dir):
        base_app_src_dir = os.path.basename(full_app_src_dir)
except:
    pass

print(base_app_src_dir + ".code-workspace")
