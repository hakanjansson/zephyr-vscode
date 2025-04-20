# Copyright (C) 2024 Infineon Technologies

# SPDX-License-Identifier: Apache-2.0

# Generates Visual Studio Code workspace files for Zephyr application

include_guard(GLOBAL)

# Load certain environment variables for use in template variable replacement
function(_vscode_workspace_load_env_variables)
  set(ENV_PWD "${VSCODE_WORKSPACE_CWD}")
  set(ENV_PATH "$ENV{PATH}")
  set(ENV_VIRTUAL_ENV "$ENV{VIRTUAL_ENV}")
  set(ENV_PYTHONHOME "$ENV{PYTHONHOME}")

  # Convert Windows paths to avoid '\' in json
  if(CMAKE_HOST_WIN32)
    cmake_path(CONVERT "${ENV_PWD}" TO_CMAKE_PATH_LIST ENV_PWD)
    cmake_path(CONVERT "${ENV_PATH}" TO_CMAKE_PATH_LIST ENV_PATH)
    cmake_path(CONVERT "${ENV_VIRTUAL_ENV}" TO_CMAKE_PATH_LIST ENV_VIRTUAL_ENV)
    cmake_path(CONVERT "${ENV_PYTHONHOME}" TO_CMAKE_PATH_LIST ENV_PYTHONHOME)
  endif()

  # Copy env values to parent scope
  set(ENV_PWD "${ENV_PWD}" PARENT_SCOPE)
  set(ENV_PATH "${ENV_PATH}" PARENT_SCOPE)
  set(ENV_VIRTUAL_ENV "${ENV_VIRTUAL_ENV}" PARENT_SCOPE)
  set(ENV_PYTHONHOME "${ENV_PYTHONHOME}" PARENT_SCOPE)

endfunction()

# Generate workspace from string json_str. The string should follow the VS Code multi-root workspace
# file schema, see below:
# ~~~
# {
# 	"folders": [],
# 	"settings": {},
# 	"launch": {
# 		"configurations": [],
# 		"compounds": []
# 	},
# 	"tasks": {
# 		"tasks": [],
# 		"input": []
# 	}
# }
# ~~~
function(_vscode_workspace_write json_str)
  if(CONFIG_VSCODE_WORKSPACE_MULTIROOT)
    set(workspace_full_filename "${VSCODE_WORKSPACE_LOCATION}/${CONFIG_VSCODE_WORKSPACE_FILENAME}")
    file(WRITE "${workspace_full_filename}" "${json_str}")
  else()
    foreach(section settings tasks launch extensions)
      string(JSON tmp_str ERROR_VARIABLE err GET "${json_str}" "${section}")
      if(NOT err)
        file(WRITE "${VSCODE_WORKSPACE_LOCATION}/.vscode/${section}.json" "${tmp_str}")
      endif()
    endforeach()
  endif()
endfunction()

# Reads existing VS Code workspace and returns it in out_json_str.
function(_vscode_workspace_read out_json_str)
  set(workspace_full_filename "${VSCODE_WORKSPACE_LOCATION}/${CONFIG_VSCODE_WORKSPACE_FILENAME}")
  if(CONFIG_VSCODE_WORKSPACE_MULTIROOT AND EXISTS "${workspace_full_filename}")
    # Read existing multi-root workspace file
    file(READ "${workspace_full_filename}" json_str)

    # Check if the existing file appears to be a valid JSON
    string(JSON dummy ERROR_VARIABLE err SET "${json_str}" "dummy" 0)
    if(err)
      message(FATAL_ERROR "Invalid JSON workspace file exists: ${workspace_full_filename}")
    endif()
  elseif(NOT CONFIG_VSCODE_WORKSPACE_MULTIROOT AND EXISTS "${VSCODE_WORKSPACE_LOCATION}/.vscode")
    set(json_str "{}")
    # Read settings
    foreach(section settings tasks launch extensions)
      if(EXISTS "${VSCODE_WORKSPACE_LOCATION}/.vscode/${section}.json")
        file(READ "${VSCODE_WORKSPACE_LOCATION}/.vscode/${section}.json" tmp_str)
        string(JSON json_str SET "${json_str}" "${section}" "${tmp_str}")
      endif()
    endforeach()
  else()
    # No existing workspace found - return an empty one
    set(json_str "{}")
  endif()
  set(${out_json_str} "${json_str}" PARENT_SCOPE)
endfunction()

# Adds new_element to array if no identical element already exists in array
function(_vscode_workspace_json_array_add_if_new out_array array new_element new_element_type)
  set(already_exists FALSE)
  string(JSON array_len LENGTH "${array}")

  # Prepare element for handling by string JSON subcommands
  if(new_element_type MATCHES STRING)
    set(new_element "\"${new_element}\"")
  elseif(new_element_type MATCHES BOOLEAN)
    if(new_element)
      set(new_element "true")
    else()
      set(new_element "false")
    endif()
  endif()

  # Iterate over existing array if not empty
  if("${array_len}" GREATER 0)
    math(EXPR last_i "${array_len}-1")
    foreach(i RANGE ${last_i})
      string(JSON existing_element_type TYPE "${array}" ${i})
      # Only need to compare elements of same type
      if(new_element_type MATCHES "${existing_element_type}")
        string(JSON existing_element GET "${array}" ${i})
        if(new_element_type MATCHES STRING)
          set(existing_element "\"${existing_element}\"")
        elseif(new_element_type MATCHES BOOLEAN)
          if(existing_element)
            set(existing_element "true")
          else()
            set(newexisting_element_element "false")
          endif()
        endif()
        string(JSON eq EQUAL "${existing_element}" "${new_element}")
        if(eq)
          set(already_exists TRUE)
          break()
        endif()
      endif()
    endforeach()
  endif()
  if(NOT already_exists)
    string(JSON ${out_array} SET ${array} ${array_len} ${new_element})
    set(${out_array} ${${out_array}} PARENT_SCOPE)
  endif()
endfunction()

# Does a recursive merge of two JSON objects. Elements in object2 takes priority over elements in
# object1.
function(_vscode_workspace_json_merge_objects out_object_name object1 object2)

  # Start by initially adding all elements from object1
  set(out_object ${object1})

  # Iterate over object2's elements
  string(JSON len LENGTH "${object2}")
  if(len GREATER 0)
    math(EXPR last_i "${len}-1")
    foreach(i RANGE ${last_i})
      string(JSON name MEMBER "${object2}" ${i})
      # Get element type: NULL, NUMBER, STRING, BOOLEAN, ARRAY, or OBJECT
      string(JSON type TYPE "${object2}" "${name}")
      string(JSON object2_value GET "${object2}" "${name}")
      if(type MATCHES OBJECT)
        # Get existing object with same name in object1, if any
        string(JSON object1_value ERROR_VARIABLE err GET "${object1}" "${name}")
        if(err)
          # No existing object found in object1, just pick the one from object2 to the output
          set(merged_object "${object2_value}")
        else()
          # Object with same name exists in both object1 and object2, do recursive merge of objects
          _vscode_workspace_json_merge_objects(merged_object "${object1_value}" "${object2_value}")
        endif()
        string(JSON out_object SET "${out_object}" "${name}" "${merged_object}")
      elseif(type MATCHES ARRAY)
        # Get existing array with same name in object1, if any
        string(JSON object1_value ERROR_VARIABLE err GET "${object1}" "${name}")
        if(err)
          # No existing array found in object1, just pick the one from object2 to the output
          set(merged_array "${object2_value}")
        else()
          # Array with same name exists in both object1 and object2, merge arrays but remove
          # duplicates

          # Start with all from object1
          set(merged_array "${object1_value}")

          # Iterate over object2 and all unique elements
          string(JSON num_elements LENGTH "${object2_value}")
          if(num_elements GREATER 0)
            math(EXPR last_j "${num_elements}-1")
            foreach(j RANGE ${last_j})
              string(JSON element GET "${object2_value}" ${j})
              string(JSON element_type TYPE "${object2_value}" ${j})
              _vscode_workspace_json_array_add_if_new(merged_array "${merged_array}" "${element}"
                                                      "${element_type}")
            endforeach()
          endif()
        endif()
        string(JSON out_object SET "${out_object}" "${name}" "${merged_array}")
      elseif(type MATCHES BOOLEAN)
        if(object2_value)
          string(JSON out_object SET "${out_object}" "${name}" "true")
        else()
          string(JSON out_object SET "${out_object}" "${name}" "false")
        endif()
      elseif(type MATCHES STRING)
        string(JSON out_object SET "${out_object}" "${name}" "\"${object2_value}\"")
      else() # NULL or NUMBER
        string(JSON out_object SET "${out_object}" "${name}" "${object2_value}")
      endif()
    endforeach()
  endif()
  set(${out_object_name} "${out_object}" PARENT_SCOPE)
endfunction()

# Merges the content of the JSON string str into the generated workspace.
function(vscode_workspace_add_json_string str)
  _vscode_workspace_read(existing_object)
  _vscode_workspace_json_merge_objects(new_object "${existing_object}" "${str}")
  _vscode_workspace_write("${new_object}")

endfunction()

# Reads JSON file "filename" and evaluates any variable references. File is expected to follow the
# VS Code multi-root workspace file schema. Merges content into the generated workspace.
function(vscode_workspace_add_json_file filename)
  file(READ "${filename}" str)
  # Load local variables before doing variable replacement
  _vscode_workspace_load_env_variables()
  string(CONFIGURE "${str}" str @ONLY ESCAPE_QUOTES)
  vscode_workspace_add_json_string("${str}")
endfunction()

# Sets up the inital workspace based on either an existing workspace or an empty workspace. If
# templates are to be used then the elements from the generic template are added to the workspace.
function(_vscode_workspace_init)
  # Store current working directory in cache
  if(CMAKE_HOST_WIN32)
    execute_process(COMMAND CMD /c cd OUTPUT_VARIABLE cwd OUTPUT_STRIP_TRAILING_WHITESPACE)
  else()
    set(cwd "$ENV{PWD}")
  endif()
  set(VSCODE_WORKSPACE_CWD "${cwd}" CACHE INTERNAL
                                          "Current working directory of west/cmake command")

  cmake_path(ABSOLUTE_PATH CONFIG_VSCODE_WORKSPACE_LOCATION BASE_DIRECTORY "${cwd}" OUTPUT_VARIABLE
             location)
  set(VSCODE_WORKSPACE_LOCATION "${location}" CACHE INTERNAL
                                                    "Absolute path to generated workspace location")

  # Get existing workspace or a new empty one
  _vscode_workspace_read(json_str)
  _vscode_workspace_write("${json_str}")
endfunction()

# Entry point
_vscode_workspace_init()
