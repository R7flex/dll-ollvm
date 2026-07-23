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

On an obfuscated menu DLL, opening a page with **two comboboxes at once** crashed (Visuals tab: box-mode + another mode combobox). One combobox on the page was fine.

Cause was not a classic buffer overflow in the mapper. The menu keeps shared popup / input state (`combobox_open_id`, click routing, draw-on-top popup). Two live comboboxes on the same frame fight that state; under obfuscated control flow the bad path shows up as an instant crash when switching tabs.

**Do not put two comboboxes on the same menu page** unless you fix the popup state machine. Same for stacking combobox + heavy color-picker popup logic on one view.

## Build plugin

```bat
cmake -S plugin -B build -G "Visual Studio 17 2022" -A x64 -DLT_LLVM_INSTALL_DIR=C:\path\to\LLVM-18.1.5-dev
cmake --build build --config Release
```

SDK needs `LLVM_EXPORT_SYMBOLS_FOR_PLUGINS=ON`. On Windows link the plugin against `opt.lib`.

`scripts/` is optional local tooling.
