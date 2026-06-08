# spektrafilm OFX

spektrafilm OFX is a native OpenFX plugin project built from the `spektrafilm`
film-simulation codebase. It is intended for host applications such as DaVinci
Resolve or Nuke and provides Metal/Vulkan-accelerated film, print, scan, grain, halation,
diffusion, color-management, and LUT-export workflows on macOS and Windows.

## Relationship to Andrea Volpato's spektrafilm

This project is an expansion of
[spektrafilm by Andrea Volpato](https://github.com/andreavolpato/spektrafilm).
The original project provides the research foundation, Python implementation,
profile-generation workflow, and much of the film-density modeling direction.

The OFX work in this directory ports and extends that idea into a native plugin
for video applications. The main goals are:

1. Stay true to the spectral and density-based character of the original model.
2. Expand upon the controls for photochemical developemnt simulation (e.g. adding push/pull)
3. Make the pipeline usable in professional video and finishing workflows.
4. Keep spacial effects resolution-independant (1080p and 2160p sample the same virtual film negative, just at different densities)
5. Leverage Apple's Metal GPU stack on macOS and Vulkan compute for Windows and Linux workflows.
6. Provide ready to use OFX binaries for non developers.
7. Keep tools in active development and research controls in a separate dev
   build.

## Binary Downloads and Product Page

Prebuilt binaries, release information, and product-facing documentation are available at:

<https://spektrafilm.114c.de>

The public binary packages are intended for users who only want to install the
OFX plugin. Building from source is mainly useful for development, verification,
custom resources, or local experimental builds.

## Main Features

The OFX plugin adds several workflow and model extensions on top of the
base `spektrafilm` framework. For a general project overview visit 
[Andrea Volpato's page](https://github.com/andreavolpato/spektrafilm) or read the documentation in [`documentation/`](documentation/).

### Color Management

The plugin includes explicit input and output color-management controls for
common camera, scene-linear, scene-log, SDR display, and HDR output paths. The
pipeline decodes input into a scene-referred working representation, runs the
film and print model, then encodes the selected output format.

The available output formats are:

| Format | Purpose |
| --- | --- |
| `Display Out SDR` | A finished display-referred SDR output. |
| `RCM` | Resolve Color Management mode. The selected timeline color space is decoded as input and encoded back as output, with no separate output color-space selector. |
| `Display Out HDR` | A finished display-referred HDR output using Rec.2100 PQ or HLG controls. |

### LUT Export

The `Manage` group includes a LUT export path for display-referred SDR looks.
Exports are rendered through the native Metal color pipeline as `.cube` LUTs. 
Spatial and stochastic effects such as grain, halation, diffusion, scanner blur, 
and similar image-dependent operations are excluded from the exported LUT
as they go beyond the scope of LUT capabilites.

The LUTs are designed to easily work for dailies, on-set monitoring, cross-platform editing and many other workflows.

For spatial effects, `Film Format` defines the shared virtual film gate used by grain, halation, diffusion, DIR, and scanner optics. Crops and enlarger transforms sample smaller regions of that same negative; output resolution only changes sampling density.

### Push and Pull Modes

The film-development controls include two push/pull approaches:

| Mode | Description |
| --- | --- |
| `Standard` | The more straightforward gamma/timing-style push/pull model. It is intended to be stable and predictable. |
| `Experimental` | A layer- and tone-region-dependent warp that often achieves looks closer to real push/pull references. |

Print/paper push and pull is separate from film push and pull. Film push/pull
acts around negative development. Print push/pull acts around paper development.

### Printer Lights

The project contains a printer-light system for APD-based print timing comparable to motion picture printers. 
It uses printer points where one point equals `1/12` stop of light, matching the common lab timing
unit.

This feature depends on SMPTE ST 2065-2 Academy Printing Density data. The relevant
CSV files are licensed standards material and are not redistributed in this
public repository.

Public source builds without those CSV files still build successfully, but the
printer-density mode and printer-point controls will be disabled and the build
prints a clear notice when the files are missing.

If you have your own licensed copies of the CSV files attached to ST 2065-2, place them here
before configuring the build:

```text
Resources/data/standards/smpte_st_2065_2/st2065-2a-2020.csv
Resources/data/standards/smpte_st_2065_2/st2065-2b-2020.csv
```

Then re-run CMake from a clean build directory. When both files are present, the
generated profile counts header enables the Academy Printer Density path and the
printer-light controls become available in the relevant plugin flavors.

### Bleach Bypass Controls (Experimental)

The native renderer has experimental negative and print bleach-bypass controls
available in the `spektrafilm dev` build. They are an attempt to model retained silver in the
film or print path, but this area is not yet backed by enough stock- and/or
process-specific measured data.

For that reason, these controls should not be treated as representative lab
controls but as a playful first attempt at modeling this process. They are not exposed 
in the normal public `spektrafilm flow` and `spektrafilm` builds.

## Project Layout

Important paths in this directory:

| Path | Purpose |
| --- | --- |
| `CMakeLists.txt` | Main build definition for the OFX bundles, Metal library, generated data, and harnesses. |
| `build_macos.sh` | Convenience build script for local macOS builds. |
| `tools/package_macos_release.sh` | Signed macOS release packager that builds both public `.ofx.bundle` plugins, creates a notarized installer package, and writes the public ZIP. |
| `tools/package_windows_release.ps1` | Windows release packager that builds both public `.ofx.bundle` plugins and writes the public ZIP with an inspectable install script. |
| `src/SpektraFilmPlugin.cpp` | OFX entry points, parameter definitions, flavor visibility, render dispatch, defaults, clipboard handling, and LUT export wiring. |
| `src/SpektraMetalRenderer.mm` | Objective-C++ Metal renderer implementation and CPU-side render orchestration. |
| `src/SpektraMetalRenderer.h` | Renderer API used by the OFX host side and the local harnesses. |
| `src/SpektraVulkanRenderer.cpp` | Early Windows/Linux Vulkan compute backend and copy-validation image I/O path. |
| `src/SpektraVulkanRenderer.h` | Vulkan renderer declaration behind the shared renderer interface. |
| `src/SpektraParameters.h` | Shared render parameter types and enums. |
| `src/SpektraProfileCurves.h` | Declarations for generated stock/profile tables. |
| `src/SpektraTooltips.h` | User-facing control help text. |
| `shaders/SpektraFilm.metal` | Metal kernels for the film, print, scan, grain, halation, diffusion, and utility passes. |
| `Resources/data/profiles/` | Self-contained film and paper profile JSON files used by the OFX build. |
| `Resources/data/filters/` | Filter data used for enlarger, print, neutral filters, heat absorption, and lens transmission. |
| `Resources/data/luts/` | Spectral upsampling LUT resources used during native table generation. |
| `Resources/data/standards/` | Optional standards-derived data. Licensed ST 2065-2 CSVs belong here. |
| `Resources/icons/` | SVG and PNG plugin icons. |
| `Resources/Info.plist.in` | macOS bundle plist template. |
| `Resources/plugin_manifest.json.in` | Plugin manifest template copied into each bundle. |
| `tools/generate_profile_curves.py` | Generates native C++ profile tables, color-space tables, APD tables, and the Hanatos LUT resource. |
| `tools/ofx_stock_lists.py` | Film and paper stock ordering for OFX plugins. |
| `tools/export_reference_cases.py` | Exports reference cases from the Python model for comparison work. |
| `tools/SpektraMetalPerfHarness.mm` | Synthetic Metal performance harness for debugging and performance hunting. |
| `tools/run_final_core_profile.py` | Focused fused/staged Metal profiling workflow for the final film-density core. |
| `tools/perf_candidates_final_core.json` | Parity-gated exact and approximate final-core optimization candidates. |
| `tools/SpektraMetalEvaluationHarness.mm` | Native evaluation harness. |
| `tools/SpektraVulkanCopyHarness.cpp` | Windows/Linux Vulkan copy-validation smoke harness. |
| `tools/SpektraVariantGenerator.mm` | Generates rendered variants for stock/look inspection (used for generating images of stocks for product website). |
| `tests/` | Python tests for build wiring, resource generation, parameter metadata, and source invariants. |
| `third_party/openfx/` | Vendored OpenFX SDK headers and support code. (OFX_Release_1.5.1)|
| `Legal/` | Binary distribution notices, exported LUT license terms, and third-party notices. |
| `documentation/` | Manual and user-facing documentation for the OFX plugin. |

## Build Requirements

The macOS source build expects:

1. macOS.
2. Xcode Command Line Tools or Xcode.
3. Apple's Metal toolchain available through `xcrun`.
4. CMake `3.24` or newer.
5. Python with the OFX build-time table generation dependencies installed:
   `numpy`, `scipy`, and `colour-science`.
6. libpng discoverable by CMake for the variant generator target.
7. OpenFX SDK headers (OFX_Release_1.5.1).

The Windows source build expects:

1. Windows 10 or newer.
2. Visual Studio 2022 C++ build tools, Ninja, or another CMake-supported C++17 toolchain.
3. Vulkan SDK with the Vulkan loader, headers, and `glslc` or `glslangValidator`.
4. CMake `3.24` or newer.
5. Python with the OFX build-time table generation dependencies installed:
   `numpy`, `scipy`, and `colour-science`.
6. OpenFX SDK headers (OFX_Release_1.5.1).

The Linux developer source build expects:

1. Linux x86_64.
2. GCC, Clang, Ninja, or another CMake-supported C++17 toolchain.
3. Vulkan loader and development headers plus `glslc` or `glslangValidator`
   from the Vulkan SDK or distribution packages.
4. CMake `3.24` or newer.
5. Python with the OFX build-time table generation dependencies installed:
   `numpy`, `scipy`, and `colour-science`.
6. OpenFX SDK headers (OFX_Release_1.5.1).

The OFX build prefers the repository virtual environment at `../../.venv/bin/python`
on Unix-like platforms and `../../.venv/Scripts/python.exe` on Windows when it
exists. Otherwise CMake falls back to the Python interpreter found by
`find_package(Python3)`. CMake checks for the build-time Python packages during
configure and prints the matching `pip install` command if they are missing.

## Setup From a Fresh Checkout
For ease of use, I developed this project from within Andrea's spektrafilm repository root. To follow the below instructions, pull the latest version of spektrafilm and place the contents of this repo at OFX/SpektraFilm.

From the spektrafilm root, create or sync the Python environment first. This
project uses the Python package for build-time table generation.

Using `uv`:

```sh
uv sync --extra dev
```

Or with a manually managed Python 3.13 environment:

```sh
python -m pip install -e ".[dev]"
```

For an OFX-only build environment, the full GUI/image stack is not required:

```sh
python -m pip install numpy scipy colour-science
```

Then build the OFX project:

```sh
cd OFX/SpektraFilm
./build_macos.sh
```

The script configures CMake, builds the plugin targets, and produces local
`.ofx.bundle` outputs. It does not sign with Developer ID, notarize, or write
the public macOS installer ZIP.

To create the signed public macOS release ZIP, first create a notarytool
keychain profile, then run the release packager with your Developer ID
identities:

```sh
xcrun notarytool store-credentials spektrafilm-notary

SPEKTRAFILM_DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)" \
SPEKTRAFILM_DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)" \
SPEKTRAFILM_NOTARY_PROFILE="spektrafilm-notary" \
./tools/package_macos_release.sh
```

The output is a single notarized installer package that installs both public
macOS plugins into `/Library/OFX/Plugins`.

On Windows, run the PowerShell build script instead:

```powershell
cd OFX\SpektraFilm
.\build_windows.ps1
```

The Windows script builds local `Contents\Win64` OFX bundles for development.
It does not create the public website ZIP.

To create the public Windows release ZIP, run the release packager:

```powershell
.\tools\package_windows_release.ps1
```

The generated zip contains both public Windows `.ofx.bundle` directories, `install.bat`,
manual, install instructions, and legal notices. The batch script can be
inspected before running; it elevates, removes old public spektrafilm bundles,
and copies the new bundles into
`C:\Program Files\Common Files\OFX\Plugins`.


On Linux, use the manual CMake flow. The build creates local
`Contents/Linux-x86-64` OFX bundles for development and emits
`SpektraVulkanCopyHarness` for the same Vulkan smoke coverage. Linux release
packaging is not provided in this phase.

## Manual CMake Build

For a more explicit build:

```sh
cd OFX/SpektraFilm
cmake -S . -B build
cmake --build build --parallel
```

To install the built OFX bundles into the system OFX plugin directory:

```sh
cmake --install build
```

The default install destinations are:

```text
macOS:   /Library/OFX/Plugins
Windows: C:/Program Files/Common Files/OFX/Plugins
Linux:   /usr/OFX/Plugins
```

Depending on your system permissions, installation may require elevated rights.


## Plugin Flavors

The build defines three OFX bundle targets:

| Target | Artifact name | Bundle label | Plugin identifier | Public package |
| --- | --- | --- | --- | --- |
| `spektrafilm_flow` | `spektrafilm_flow` | `spektrafilm flow` | `org.spektrafilm.flow` | Yes |
| `spektrafilm` | `spektrafilm` | `spektrafilm` | `org.spektrafilm` | Yes |
| `spektrafilm_dev` | `spektrafilm_dev` | `spektrafilm dev` | `org.spektrafilm.dev` | No |

All three are compiled from the same source. Flavor-specific behavior is
controlled through compile definitions and parameter visibility rules in
`src/SpektraFilmPlugin.cpp`.

## Legal and Redistribution Notes

1. The public source tree does not redistribute licensed SMPTE ST 2065-2 CSV
   files.
2. Official binary distributions may include bundled resources covered by the
   notices in `Legal/`.
3. LUT files exported from the plugin are governed by
   `Legal/SPEKTRAFILM_OFX_LUT_LICENSE.txt`.
4. The vendored OpenFX SDK carries its own notices under `third_party/openfx/`.

## Development Notes

The plugin is still an active development project. The public flavors prioritize
controls that are useful and reasonably defensible in grading workflows. The dev
flavor keeps deeper controls available so that modeling decisions can be tested
without committing every experiment to the public UI.

Have fun and thank you for creating with spektrafilm!
