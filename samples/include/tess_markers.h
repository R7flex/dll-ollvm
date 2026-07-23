#pragma once

#if defined(__clang__)
#  define TESS_SKIP \
    __attribute__((annotate("tess_skip")))
#  define TESS_SKIP_BEGIN \
    _Pragma("clang attribute push (__attribute__((annotate(\"tess_skip\"))), apply_to = function)")
#  define TESS_SKIP_END \
    _Pragma("clang attribute pop")
#  define TESS_PROTECT \
    __attribute__((annotate("tess_protect")))
#  define TESS_OBF \
    __attribute__((annotate("tess_obf")))
#else
#  define TESS_SKIP
#  define TESS_SKIP_BEGIN
#  define TESS_SKIP_END
#  define TESS_PROTECT
#  define TESS_OBF
#endif
