# Copyright (C) 2024 Infineon Technologies
# SPDX-License-Identifier: Apache-2.0

vscode_workspace_add_json_file("${CMAKE_CURRENT_LIST_DIR}/zephyr.code-workspace")

set(board_template_filename
    "${CMAKE_CURRENT_LIST_DIR}/${BOARD}.code-workspace")

if(EXISTS "${board_template_filename}")
  vscode_workspace_add_json_file(
    "${board_template_filename}")
endif()
