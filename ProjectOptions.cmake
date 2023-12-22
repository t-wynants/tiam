include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(tiam_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(tiam_setup_options)
  option(tiam_ENABLE_HARDENING "Enable hardening" ON)
  option(tiam_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    tiam_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    tiam_ENABLE_HARDENING
    OFF)

  tiam_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR tiam_PACKAGING_MAINTAINER_MODE)
    option(tiam_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(tiam_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(tiam_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(tiam_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(tiam_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(tiam_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(tiam_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(tiam_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(tiam_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(tiam_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(tiam_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(tiam_ENABLE_PCH "Enable precompiled headers" OFF)
    option(tiam_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(tiam_ENABLE_IPO "Enable IPO/LTO" ON)
    option(tiam_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(tiam_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(tiam_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(tiam_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(tiam_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(tiam_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(tiam_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(tiam_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(tiam_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(tiam_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(tiam_ENABLE_PCH "Enable precompiled headers" OFF)
    option(tiam_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      tiam_ENABLE_IPO
      tiam_WARNINGS_AS_ERRORS
      tiam_ENABLE_USER_LINKER
      tiam_ENABLE_SANITIZER_ADDRESS
      tiam_ENABLE_SANITIZER_LEAK
      tiam_ENABLE_SANITIZER_UNDEFINED
      tiam_ENABLE_SANITIZER_THREAD
      tiam_ENABLE_SANITIZER_MEMORY
      tiam_ENABLE_UNITY_BUILD
      tiam_ENABLE_CLANG_TIDY
      tiam_ENABLE_CPPCHECK
      tiam_ENABLE_COVERAGE
      tiam_ENABLE_PCH
      tiam_ENABLE_CACHE)
  endif()

  tiam_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (tiam_ENABLE_SANITIZER_ADDRESS OR tiam_ENABLE_SANITIZER_THREAD OR tiam_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(tiam_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(tiam_global_options)
  if(tiam_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    tiam_enable_ipo()
  endif()

  tiam_supports_sanitizers()

  if(tiam_ENABLE_HARDENING AND tiam_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR tiam_ENABLE_SANITIZER_UNDEFINED
       OR tiam_ENABLE_SANITIZER_ADDRESS
       OR tiam_ENABLE_SANITIZER_THREAD
       OR tiam_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${tiam_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${tiam_ENABLE_SANITIZER_UNDEFINED}")
    tiam_enable_hardening(tiam_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(tiam_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(tiam_warnings INTERFACE)
  add_library(tiam_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  tiam_set_project_warnings(
    tiam_warnings
    ${tiam_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(tiam_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(tiam_options)
  endif()

  include(cmake/Sanitizers.cmake)
  tiam_enable_sanitizers(
    tiam_options
    ${tiam_ENABLE_SANITIZER_ADDRESS}
    ${tiam_ENABLE_SANITIZER_LEAK}
    ${tiam_ENABLE_SANITIZER_UNDEFINED}
    ${tiam_ENABLE_SANITIZER_THREAD}
    ${tiam_ENABLE_SANITIZER_MEMORY})

  set_target_properties(tiam_options PROPERTIES UNITY_BUILD ${tiam_ENABLE_UNITY_BUILD})

  if(tiam_ENABLE_PCH)
    target_precompile_headers(
      tiam_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(tiam_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    tiam_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(tiam_ENABLE_CLANG_TIDY)
    tiam_enable_clang_tidy(tiam_options ${tiam_WARNINGS_AS_ERRORS})
  endif()

  if(tiam_ENABLE_CPPCHECK)
    tiam_enable_cppcheck(${tiam_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(tiam_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    tiam_enable_coverage(tiam_options)
  endif()

  if(tiam_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(tiam_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(tiam_ENABLE_HARDENING AND NOT tiam_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR tiam_ENABLE_SANITIZER_UNDEFINED
       OR tiam_ENABLE_SANITIZER_ADDRESS
       OR tiam_ENABLE_SANITIZER_THREAD
       OR tiam_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    tiam_enable_hardening(tiam_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
