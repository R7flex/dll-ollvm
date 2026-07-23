# LLVMObfuscationx

LLVM 18 New Pass Manager plugin for Windows.

Tested on **manually mapped DLLs** (injectors that only do reloc / optional IAT / `DllMain` — no CRT startup).

## How it works

1. `clang` emits LLVM bitcode
2. `opt` loads `LLVMObfuscationx.dll` and rewrites the IR
3. `llc` → `.obj` → link

Passes run on IR before codegen. The PE itself is not patched afterward.

| Pass | name |
|------|------|
| Instruction substitution | `tess-sub` |
| Bogus control flow | `tess-bcf` |
| Control-flow flattening | `tess-fla` |
| Strip ctors / dead locals | `tess-trim` |
| All | `tess-obf` |

### Example (decompiled)

What a small helper can look like after the passes (IDA, x64):

```c
// local variable allocation has failed, the output may be wrong!
__int64 __fastcall sub_180011D60(_QWORD *_RCX, _WORD *a2, double _XMM2_8)
{
  __int64 v8; // rcx
  __int64 v12; // rax
  __int64 result; // rax
  __int128 v17; // [rsp+70h] [rbp-78h] BYREF
  _QWORD v18[2]; // [rsp+80h] [rbp-68h] BYREF
  __int128 v19; // [rsp+90h] [rbp-58h] BYREF
  __int128 v20; // [rsp+A0h] [rbp-48h] BYREF
  __int128 v21; // [rsp+B0h] [rbp-38h] BYREF
  __int128 v22; // [rsp+C0h] [rbp-28h] BYREF
  __int128 v23; // [rsp+D0h] [rbp-18h] BYREF

  _RSI = _RCX;
  __asm
  {
    vmovsd  xmm0, qword ptr [rcx+30h]
    vaddsd  xmm0, xmm0, cs:qword_180028040
    vaddsd  xmm0, xmm0, cs:qword_1800280F8
    vmovsd  xmm1, qword ptr [rcx+38h]
  }
  v8 = *_RCX;
  __asm
  {
    vxorps  xmm2, xmm2, xmm2
    vmovaps [rsp+0E8h+var_18], xmm2
    vmovaps [rsp+0E8h+var_28], xmm2
    vmovaps [rsp+0E8h+var_38], xmm2
    vmovaps xmm3, cs:xmmword_1800281D0
    vmovaps [rsp+0E8h+var_48], xmm3
    vmovddup xmm3, cs:qword_180028280
    vmovaps [rsp+0E8h+var_58], xmm3
    vmovsd  [rsp+0E8h+var_68], xmm0
    vmovsd  [rsp+0E8h+var_60], xmm1
    vmovaps [rsp+0E8h+var_78], xmm2
  }
  if ( *a2 )
  {
    v12 = 1;
    while ( a2[v12++] != 0 )
      ;
    DWORD2(v17) = v12;
    HIDWORD(v17) = v12;
    *(_QWORD *)&v17 = a2;
  }
  sub_180011EB0(
    v8,
    _RSI[1],
    (unsigned int)&v17,
    (unsigned int)v18,
    (__int64)&v19,
    (__int64)&v20,
    0,
    (__int64)&v21,
    (__int64)&v22,
    0,
    0,
    0,
    (__int64)&v23);
  __asm
  {
    vmovsd  xmm0, qword ptr [rsi+38h]
    vaddsd  xmm0, xmm0, cs:qword_180028000
    vmovsd  qword ptr [rsi+38h], xmm0
  }
  result = *((int *)_RSI + 33);
  __asm { vmovsd  qword ptr [rsi+rax*8+0C8h], xmm0 }
  return result;
}
```

## Usage

LLVM **18.1.5** with plugin support. Drop `LLVMObfuscationx.dll` next to `opt.exe`.

```bat
clang -c -emit-llvm -O1 --target=x86_64-pc-windows-msvc -o in.bc file.cpp
opt -passes="default<O2>" in.bc -o mid.bc
opt -load-pass-plugin=LLVMObfuscationx.dll -passes=tess-obf mid.bc -o out.bc
llc -filetype=obj -mtriple=x86_64-pc-windows-msvc -O2 out.bc -o out.obj
```

Skip a function:

```cpp
__attribute__((annotate("tess_skip")))
void keep_plain() {}
```

See `samples/include/tess_markers.h`.

## Manual map + clang — watch out

Manual mappers usually **do not** run `.CRT` / `llvm.global_ctors`. If you leave dynamic C++ global constructors in the binary, they never run after map → zeros / wrong state / crash.

This plugin’s `tess-trim` **deletes** `llvm.global_ctors` / `dtors` on purpose so the PE matches freestanding `/NODEFAULTLIB` mapping. That means:

- Globals with non-trivial constructors stay uninitialized unless you construct them at runtime
- Prefer POD (`float r,g,b,a`) or functions that return colors/values on the stack
- `inline const SomeType x = {...}` is unsafe if `SomeType` has a constructor
- No exceptions / no reliance on CRT init, TLS callbacks, or atexit
- Do not flatten `DllMain` unless you know what you are doing (`tess-fla-entry` is off by default)
- Keep stack-heavy / UI / hook paths on `tess_skip` if they misbehave under `fla`/`bcf`

Also: plugin and `opt.exe` must come from the **same** LLVM build. Mixing the official tools-only installer with a random plugin DLL will crash on load.

## UI note (tested)

Not a mapper overflow. Root cause is **shared exclusive UI state**: a single “active overlay” slot, one input path, one draw-on-top popup. Two widgets that both claim that slot on the same page corrupt open-id / hit-testing / overlay pointers. Obfuscated CFG just makes the bad path crash immediately when the page opens.

One exclusive popup-style control per page, or give each overlay its own state. Heavy menu/input code can also take `tess_skip`.

## Build plugin

```bat
cmake -S plugin -B build -G "Visual Studio 17 2022" -A x64 -DLT_LLVM_INSTALL_DIR=C:\path\to\LLVM-18.1.5-dev
cmake --build build --config Release
```

SDK needs `LLVM_EXPORT_SYMBOLS_FOR_PLUGINS=ON`. On Windows link the plugin against `opt.lib`.

`scripts/` is optional local tooling.
