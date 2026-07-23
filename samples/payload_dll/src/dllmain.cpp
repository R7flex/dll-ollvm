#include <stdint.h>

#if defined(_WIN32)
#  define PAYLOAD_EXPORT __declspec(dllexport)
#else
#  define PAYLOAD_EXPORT
#endif

static uint32_t mix(uint32_t x) {
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  return x;
}

#ifdef __cplusplus
extern "C" {
#endif

PAYLOAD_EXPORT int payload_entry(int seed) {
  uint32_t v = (uint32_t)seed;
  for (int i = 0; i < 8; ++i)
    v = mix(v + (uint32_t)i);
  return (int)(v & 0xffff);
}

#if defined(_WIN32)
#  include <windows.h>

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID reserved) {
  (void)hModule;
  (void)reserved;
  switch (reason) {
  case DLL_PROCESS_ATTACH:
  case DLL_THREAD_ATTACH:
  case DLL_THREAD_DETACH:
  case DLL_PROCESS_DETACH:
    break;
  }
  return TRUE;
}
#endif

#ifdef __cplusplus
}
#endif
