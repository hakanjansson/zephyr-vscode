# Copyright (C) 2024 Infineon Technologies
# SPDX-License-Identifier: Apache-2.0

include(vscode.cmake)

if(CONFIG_VSCODE_WORKSPACE_TEMPLATE)
  include(${CMAKE_CURRENT_LIST_DIR}/templates/templates.cmake)
endif()
