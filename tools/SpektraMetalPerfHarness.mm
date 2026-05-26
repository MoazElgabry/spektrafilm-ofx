#include "SpektraMetalRenderer.h"
#include "SpektraHarnessHostIO.h"

#import <Foundation/Foundation.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

double elapsedMs(Clock::time_point start, Clock::time_point end) {
  return std::chrono::duration<double, std::milli>(end - start).count();
}

struct Options {
  int width = 1920;
  int height = 1080;
  int warmup = 1;
  int iterations = 3;
  std::string caseName = "default-final";
  std::string resourceDir;
  std::string scratchStorage = "private";
  std::string threadgroup = "auto";
  std::string passTiming = "off";
  std::string diffusionGroupSize = "2";
  std::string scannerImageStorage = "buffer";
  std::string blurBackend = "custom";
  std::string blurDownsample = "auto";
  std::string intermediatePrecision = "float";
  std::string diffusionClusterSigma = "0.10";
  std::string halationGroupedTail = "0";
  std::string scannerMps = "0";
  std::string grainBlurRecurrence = "1";
  std::string dirTailBackend = "mps";
  std::string densityCurveLookup = "binary";
  std::string spectralTransmittance = "pow";
  std::string sourceFormat = "float";
  std::string destinationFormat = "float";
  std::string hostLayout = "contiguous";
  bool detail = false;
  bool passCounters = false;
  bool passTimingExplicit = false;
  int grainSynthesisSamples = -1;
  bool grainSynthesisLayeredOverride = false;
  bool grainSynthesisLayered = true;
  bool grainSynthesisRadiusStdDevOverride = false;
  float grainSynthesisRadiusStdDev = 0.0f;
  bool grainSynthesisObservationSigmaOverride = false;
  float grainSynthesisObservationSigmaUm = 0.0f;
  std::string grainSynthesisSampler = "r2";
  std::string grainSynthesisRadiusLut = "512";
  std::string grainSynthesisTargetStorage = "float-buffer";
  std::string grainSynthesisCellMode = "offset-list";
};

void printUsage(const char *name) {
  std::cerr
    << "Usage: " << name << " [--width N] [--height N] [--iterations N] [--warmup N]\n"
    << "       [--case default-final|production-grain|enlarged-production-grain|production-grain-no-sublayers|production-grain-no-blur|auto-exposure|halation-only|halation-boost|camera-diffusion-only|diffusion-only|print-diffusion-only|dir-only|scanner-only|scanner-glare|all-effects|all]\n"
    << "       [--resource-dir PATH] [--scratch-storage private|shared]\n"
    << "       [--threadgroup auto|16x16|32x8|8x32|64x4]\n"
    << "       [--scanner-image-storage buffer|texture]\n"
    << "       [--source-format float|half] [--destination-format float|half]\n"
    << "       [--host-layout contiguous|strided|offset]\n"
    << "       [--diffusion-group-size 1|2|4] [--pass-timing off|auto|counter|split]\n"
    << "       [--blur-backend custom|mps|auto] [--blur-downsample off|2|4|8|auto]\n"
    << "       [--intermediate-precision float|half-blur] [--diffusion-cluster-sigma off|0.05|0.10]\n"
    << "       [--halation-grouped-tail 0|1] [--scanner-mps 0|1] [--grain-blur-recurrence 0|1]\n"
    << "       [--dir-tail-backend fused|mps]\n"
    << "       [--density-curve-lookup binary|uniform-linear|uniform-nearest]\n"
    << "       [--spectral-transmittance pow|exp2|fast-exp]\n"
    << "       [--grain-synthesis-samples N] [--grain-synthesis-layered on|off]\n"
    << "       [--grain-synthesis-radius-stddev X] [--grain-synthesis-observation-sigma-um X]\n"
    << "       [--grain-synthesis-sampler r2|antithetic|sobol-blue]\n"
    << "       [--grain-synthesis-radius-lut off|256|512]\n"
    << "       [--grain-synthesis-target-storage float-buffer|half-buffer|r16-texture-array]\n"
    << "       [--grain-synthesis-cell-mode current|offset-list|threadgroup-cache]\n"
    << "       [--detail] [--pass-counters]\n";
}

bool parseInt(const char *text, int &out) {
  char *end = nullptr;
  const long value = std::strtol(text, &end, 10);
  if (!end || *end != '\0' || value <= 0 || value > 32768) {
    return false;
  }
  out = static_cast<int>(value);
  return true;
}

bool parseNonNegativeInt(const char *text, int &out) {
  char *end = nullptr;
  const long value = std::strtol(text, &end, 10);
  if (!end || *end != '\0' || value < 0 || value > 32768) {
    return false;
  }
  out = static_cast<int>(value);
  return true;
}

bool parseFloat(const char *text, float &out) {
  char *end = nullptr;
  const float value = std::strtof(text, &end);
  if (!end || *end != '\0' || !std::isfinite(value)) {
    return false;
  }
  out = value;
  return true;
}

bool parseBool(const char *text, bool &out) {
  const std::string value = text ? std::string(text) : "";
  if (value == "1" || value == "true" || value == "TRUE" || value == "yes" || value == "YES" || value == "on" || value == "ON") {
    out = true;
    return true;
  }
  if (value == "0" || value == "false" || value == "FALSE" || value == "no" || value == "NO" || value == "off" || value == "OFF") {
    out = false;
    return true;
  }
  return false;
}

bool parseArgs(int argc, const char **argv, Options &options) {
  for (int i = 1; i < argc; ++i) {
    const std::string arg = argv[i];
    auto requireValue = [&](const char *flag) -> const char * {
      if (i + 1 >= argc) {
        std::cerr << flag << " requires a value.\n";
        return nullptr;
      }
      return argv[++i];
    };

    if (arg == "--help" || arg == "-h") {
      printUsage(argv[0]);
      std::exit(0);
    } else if (arg == "--width") {
      const char *value = requireValue("--width");
      if (!value || !parseInt(value, options.width)) {
        return false;
      }
    } else if (arg == "--height") {
      const char *value = requireValue("--height");
      if (!value || !parseInt(value, options.height)) {
        return false;
      }
    } else if (arg == "--iterations") {
      const char *value = requireValue("--iterations");
      if (!value || !parseInt(value, options.iterations)) {
        return false;
      }
    } else if (arg == "--warmup") {
      const char *value = requireValue("--warmup");
      if (!value || !parseNonNegativeInt(value, options.warmup)) {
        return false;
      }
    } else if (arg == "--case") {
      const char *value = requireValue("--case");
      if (!value) {
        return false;
      }
      options.caseName = value;
    } else if (arg == "--resource-dir") {
      const char *value = requireValue("--resource-dir");
      if (!value) {
        return false;
      }
      options.resourceDir = value;
    } else if (arg == "--scratch-storage") {
      const char *value = requireValue("--scratch-storage");
      if (!value || (std::string(value) != "private" && std::string(value) != "shared")) {
        return false;
      }
      options.scratchStorage = value;
    } else if (arg == "--threadgroup") {
      const char *value = requireValue("--threadgroup");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "auto" && mode != "16x16" && mode != "32x8" && mode != "8x32" && mode != "64x4") {
        return false;
      }
      options.threadgroup = mode;
    } else if (arg == "--pass-timing") {
      const char *value = requireValue("--pass-timing");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "off" && mode != "auto" && mode != "counter" && mode != "split") {
        return false;
      }
      options.passTiming = mode;
      options.passTimingExplicit = true;
    } else if (arg == "--scanner-image-storage") {
      const char *value = requireValue("--scanner-image-storage");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "buffer" && mode != "texture") {
        return false;
      }
      options.scannerImageStorage = mode;
    } else if (arg == "--source-format") {
      const char *value = requireValue("--source-format");
      spektrafilm_harness::HostPixelFormat format;
      if (!value || !spektrafilm_harness::parseHostPixelFormat(value, format)) {
        return false;
      }
      options.sourceFormat = spektrafilm_harness::hostPixelFormatName(format);
    } else if (arg == "--destination-format") {
      const char *value = requireValue("--destination-format");
      spektrafilm_harness::HostPixelFormat format;
      if (!value || !spektrafilm_harness::parseHostPixelFormat(value, format)) {
        return false;
      }
      options.destinationFormat = spektrafilm_harness::hostPixelFormatName(format);
    } else if (arg == "--host-layout") {
      const char *value = requireValue("--host-layout");
      spektrafilm_harness::HostLayout layout;
      if (!value || !spektrafilm_harness::parseHostLayout(value, layout)) {
        return false;
      }
      options.hostLayout = spektrafilm_harness::hostLayoutName(layout);
    } else if (arg == "--diffusion-group-size") {
      const char *value = requireValue("--diffusion-group-size");
      const std::string size = value ? std::string(value) : "";
      if (size != "1" && size != "2" && size != "4") {
        return false;
      }
      options.diffusionGroupSize = size;
    } else if (arg == "--blur-backend") {
      const char *value = requireValue("--blur-backend");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "custom" && mode != "mps" && mode != "auto") {
        return false;
      }
      options.blurBackend = mode;
    } else if (arg == "--blur-downsample") {
      const char *value = requireValue("--blur-downsample");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "off" && mode != "2" && mode != "4" && mode != "8" && mode != "auto") {
        return false;
      }
      options.blurDownsample = mode;
    } else if (arg == "--intermediate-precision") {
      const char *value = requireValue("--intermediate-precision");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "float" && mode != "half-blur") {
        return false;
      }
      options.intermediatePrecision = mode;
    } else if (arg == "--diffusion-cluster-sigma") {
      const char *value = requireValue("--diffusion-cluster-sigma");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "off" && mode != "0.05" && mode != "0.10") {
        return false;
      }
      options.diffusionClusterSigma = mode;
    } else if (arg == "--halation-grouped-tail") {
      const char *value = requireValue("--halation-grouped-tail");
      bool parsed = false;
      if (!value || !parseBool(value, parsed)) {
        return false;
      }
      options.halationGroupedTail = parsed ? "1" : "0";
    } else if (arg == "--scanner-mps") {
      const char *value = requireValue("--scanner-mps");
      bool parsed = false;
      if (!value || !parseBool(value, parsed)) {
        return false;
      }
      options.scannerMps = parsed ? "1" : "0";
    } else if (arg == "--grain-blur-recurrence") {
      const char *value = requireValue("--grain-blur-recurrence");
      bool parsed = false;
      if (!value || !parseBool(value, parsed)) {
        return false;
      }
      options.grainBlurRecurrence = parsed ? "1" : "0";
    } else if (arg == "--dir-tail-backend") {
      const char *value = requireValue("--dir-tail-backend");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "fused" && mode != "mps") {
        return false;
      }
      options.dirTailBackend = mode;
    } else if (arg == "--density-curve-lookup") {
      const char *value = requireValue("--density-curve-lookup");
      std::string mode = value ? std::string(value) : "";
      if (mode == "uniform" || mode == "linear") {
        mode = "uniform-linear";
      } else if (mode == "nearest") {
        mode = "uniform-nearest";
      }
      if (mode != "binary" && mode != "uniform-linear" && mode != "uniform-nearest") {
        return false;
      }
      options.densityCurveLookup = mode;
    } else if (arg == "--spectral-transmittance") {
      const char *value = requireValue("--spectral-transmittance");
      std::string mode = value ? std::string(value) : "";
      if (mode == "fast" || mode == "fast-exp2") {
        mode = "fast-exp";
      }
      if (mode != "pow" && mode != "exp2" && mode != "fast-exp") {
        return false;
      }
      options.spectralTransmittance = mode;
    } else if (arg == "--detail") {
      options.detail = true;
    } else if (arg == "--pass-counters") {
      options.passCounters = true;
    } else if (arg == "--grain-synthesis-samples") {
      const char *value = requireValue("--grain-synthesis-samples");
      if (!value || !parseInt(value, options.grainSynthesisSamples)) {
        return false;
      }
    } else if (arg == "--grain-synthesis-layered") {
      const char *value = requireValue("--grain-synthesis-layered");
      if (!value || !parseBool(value, options.grainSynthesisLayered)) {
        return false;
      }
      options.grainSynthesisLayeredOverride = true;
    } else if (arg == "--grain-synthesis-radius-stddev") {
      const char *value = requireValue("--grain-synthesis-radius-stddev");
      if (!value || !parseFloat(value, options.grainSynthesisRadiusStdDev) || options.grainSynthesisRadiusStdDev < 0.0f) {
        return false;
      }
      options.grainSynthesisRadiusStdDevOverride = true;
    } else if (arg == "--grain-synthesis-observation-sigma-um") {
      const char *value = requireValue("--grain-synthesis-observation-sigma-um");
      if (!value || !parseFloat(value, options.grainSynthesisObservationSigmaUm) || options.grainSynthesisObservationSigmaUm < 0.0f) {
        return false;
      }
      options.grainSynthesisObservationSigmaOverride = true;
    } else if (arg == "--grain-synthesis-sampler") {
      const char *value = requireValue("--grain-synthesis-sampler");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "r2" && mode != "antithetic" && mode != "sobol-blue") {
        return false;
      }
      options.grainSynthesisSampler = mode;
    } else if (arg == "--grain-synthesis-radius-lut") {
      const char *value = requireValue("--grain-synthesis-radius-lut");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "off" && mode != "256" && mode != "512") {
        return false;
      }
      options.grainSynthesisRadiusLut = mode;
    } else if (arg == "--grain-synthesis-target-storage") {
      const char *value = requireValue("--grain-synthesis-target-storage");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "float-buffer" && mode != "half-buffer" && mode != "r16-texture-array") {
        return false;
      }
      options.grainSynthesisTargetStorage = mode;
    } else if (arg == "--grain-synthesis-cell-mode") {
      const char *value = requireValue("--grain-synthesis-cell-mode");
      const std::string mode = value ? std::string(value) : "";
      if (mode != "current" && mode != "offset-list" && mode != "threadgroup-cache") {
        return false;
      }
      options.grainSynthesisCellMode = mode;
    } else {
      std::cerr << "Unknown argument: " << arg << "\n";
      return false;
    }
  }
  return true;
}

std::vector<float> makeSyntheticFrame(int width, int height) {
  std::vector<float> pixels(static_cast<size_t>(width) * static_cast<size_t>(height) * 4u, 1.0f);
  for (int y = 0; y < height; ++y) {
    const float fy = height > 1 ? static_cast<float>(y) / static_cast<float>(height - 1) : 0.0f;
    for (int x = 0; x < width; ++x) {
      const float fx = width > 1 ? static_cast<float>(x) / static_cast<float>(width - 1) : 0.0f;
      const float edge = x > width / 2 ? 0.18f : 0.0f;
      const float chip = ((x / 96 + y / 96) & 1) ? 0.04f : 0.0f;
      float *pixel = pixels.data() + (static_cast<size_t>(y) * width + x) * 4u;
      pixel[0] = std::clamp(0.02f + 0.85f * fx + edge, 0.0f, 1.25f);
      pixel[1] = std::clamp(0.03f + 0.75f * fy + chip, 0.0f, 1.15f);
      pixel[2] = std::clamp(0.04f + 0.55f * (1.0f - fx) + 0.25f * fy, 0.0f, 1.10f);
      pixel[3] = 1.0f;
    }
  }
  return pixels;
}

spektrafilm::RenderParams baseParams() {
  spektrafilm::RenderParams params;
  params.inputColorSpace = spektrafilm::ColorSpace::LinearRec2020;
  params.outputColorSpace = spektrafilm::ColorSpace::Rec709Gamma24;
  params.grainSeed = 42u;
  params.grainAnimate = false;
  return params;
}

spektrafilm::RenderParams paramsForCase(const std::string &caseName) {
  spektrafilm::RenderParams params = baseParams();

  if (caseName == "default-final") {
    return params;
  }
  if (caseName == "production-grain") {
    params.grainModel = spektrafilm::GrainModel::Production;
    return params;
  }
  if (caseName == "enlarged-production-grain") {
    params.grainModel = spektrafilm::GrainModel::Production;
    params.enlargerScale = 4.0f;
    params.enlargerOffsetXPercent = 0.0f;
    params.enlargerOffsetYPercent = 0.0f;
    return params;
  }
  if (caseName == "grain-synthesis") {
    params.grainModel = spektrafilm::GrainModel::GrainSynthesis;
    params.grainSynthesisSamples = 64;
    params.grainSynthesisRadiusStdDevRatio = 0.0f;
    return params;
  }
  if (caseName == "grain-synthesis-hq") {
    params.grainModel = spektrafilm::GrainModel::GrainSynthesis;
    params.grainSynthesisSamples = 256;
    params.grainSynthesisRadiusStdDevRatio = 0.2f;
    params.grainSynthesisMaxGrainsPerCell = 64;
    return params;
  }
  if (caseName == "grain-synthesis-nonlayered") {
    params.grainModel = spektrafilm::GrainModel::GrainSynthesis;
    params.grainSynthesisSamples = 64;
    params.grainSynthesisRadiusStdDevRatio = 0.0f;
    params.grainSynthesisLayered = false;
    return params;
  }
  if (caseName == "production-grain-no-sublayers") {
    params.grainModel = spektrafilm::GrainModel::Production;
    params.grainSublayersEnabled = false;
    return params;
  }
  if (caseName == "production-grain-no-blur") {
    params.grainModel = spektrafilm::GrainModel::Production;
    params.grainFinalBlurUm = 0.0f;
    params.grainBlurDyeCloudsUm = 0.0f;
    params.grainMicroStructureScale = 0.0f;
    return params;
  }
  if (caseName == "auto-exposure") {
    params.autoExposure = true;
    params.autoExposureMethod = spektrafilm::AutoExposureMethod::Median;
    params.grainEnabled = false;
    params.halationEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = false;
    params.scannerEnabled = false;
    params.dirCouplersAmount = 0.0f;
    return params;
  }
  if (caseName == "halation-only") {
    params.grainEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = false;
    params.scannerEnabled = false;
    params.dirCouplersAmount = 0.0f;
    params.halationEnabled = true;
    params.scatterAmount = 1.0f;
    params.halationAmount = 1.0f;
    return params;
  }
  if (caseName == "halation-boost") {
    params.grainEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = false;
    params.scannerEnabled = false;
    params.dirCouplersAmount = 0.0f;
    params.halationEnabled = true;
    params.scatterAmount = 1.0f;
    params.halationAmount = 1.0f;
    params.halationBoostEv = 1.0f;
    return params;
  }
  if (caseName == "camera-diffusion-only" || caseName == "diffusion-only") {
    params.grainEnabled = false;
    params.halationEnabled = false;
    params.cameraDiffusionEnabled = true;
    params.cameraDiffusionStrength = 0.5f;
    params.printDiffusionEnabled = false;
    params.scannerEnabled = false;
    params.dirCouplersAmount = 0.0f;
    return params;
  }
  if (caseName == "print-diffusion-only") {
    params.grainEnabled = false;
    params.halationEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = true;
    params.printDiffusionStrength = 0.5f;
    params.scannerEnabled = false;
    params.dirCouplersAmount = 0.0f;
    return params;
  }
  if (caseName == "dir-only") {
    params.grainEnabled = false;
    params.halationEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = false;
    params.scannerEnabled = false;
    params.dirCouplersAmount = 0.6f;
    return params;
  }
  if (caseName == "scanner-only") {
    params.grainEnabled = false;
    params.halationEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = false;
    params.dirCouplersAmount = 0.0f;
    params.process = spektrafilm::ProcessMode::ScanNegative;
    params.scannerEnabled = true;
    params.scannerMtf50LpMm = 60.0f;
    params.scannerUnsharpRadiusUm = 5.0f;
    params.scannerUnsharpAmount = 0.7f;
    params.scannerWhiteCorrection = true;
    params.scannerBlackCorrection = true;
    return params;
  }
  if (caseName == "scanner-glare") {
    params.grainEnabled = false;
    params.halationEnabled = false;
    params.cameraDiffusionEnabled = false;
    params.printDiffusionEnabled = false;
    params.dirCouplersAmount = 0.0f;
    params.process = spektrafilm::ProcessMode::PrintSimulation;
    params.scannerEnabled = true;
    params.scannerMtf50LpMm = 0.0f;
    params.scannerUnsharpRadiusUm = 0.0f;
    params.scannerUnsharpAmount = 0.0f;
    params.glarePercent = 0.03f;
    return params;
  }
  if (caseName == "all-effects") {
    params.grainModel = spektrafilm::GrainModel::Production;
    params.grainSubLayerCount = 3;
    params.dirCouplersAmount = 0.6f;
    params.cameraDiffusionEnabled = true;
    params.cameraDiffusionStrength = 0.7f;
    params.printDiffusionEnabled = false;
    params.printDiffusionStrength = 0.0f;
    params.scannerEnabled = true;
    params.scannerMtf50LpMm = 60.0f;
    params.scannerUnsharpRadiusUm = 5.0f;
    params.scannerUnsharpAmount = 0.7f;
    return params;
  }

  return params;
}

std::vector<std::string> selectedCases(const std::string &caseName) {
  const std::vector<std::string> allCases = {
    "default-final",
    "production-grain",
    "enlarged-production-grain",
    "production-grain-no-sublayers",
    "production-grain-no-blur",
    "auto-exposure",
    "halation-only",
    "halation-boost",
    "camera-diffusion-only",
    "print-diffusion-only",
    "dir-only",
    "scanner-only",
    "scanner-glare",
    "all-effects",
  };
  if (caseName == "all") {
    return allCases;
  }
  const std::vector<std::string> aliasCases = {
    "diffusion-only",
  };
  const bool knownCase = std::find(allCases.begin(), allCases.end(), caseName) != allCases.end() ||
                         std::find(aliasCases.begin(), aliasCases.end(), caseName) != aliasCases.end();
  if (!knownCase) {
    return {};
  }
  return {caseName};
}

double averageLuma(const std::vector<float> &pixels) {
  double sum = 0.0;
  const size_t count = pixels.size() / 4u;
  for (size_t i = 0; i < count; ++i) {
    const float *pixel = pixels.data() + i * 4u;
    sum += 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2];
  }
  return count > 0 ? sum / static_cast<double>(count) : 0.0;
}

} // namespace

int main(int argc, const char **argv) {
  @autoreleasepool {
    Options options;
    if (!parseArgs(argc, argv, options)) {
      printUsage(argv[0]);
      return 2;
    }
    if (!options.passTimingExplicit && (options.passCounters || options.detail)) {
      options.passTiming = "auto";
    }
    if (!options.resourceDir.empty()) {
      setenv("SPEKTRAFILM_RESOURCE_DIR", options.resourceDir.c_str(), 1);
    }
    setenv("SPEKTRAFILM_SCRATCH_STORAGE", options.scratchStorage.c_str(), 1);
    setenv("SPEKTRAFILM_THREADGROUP", options.threadgroup.c_str(), 1);
    setenv("SPEKTRAFILM_SCANNER_IMAGE_STORAGE", options.scannerImageStorage.c_str(), 1);
    setenv("SPEKTRAFILM_DIFFUSION_GROUP_SIZE", options.diffusionGroupSize.c_str(), 1);
    setenv("SPEKTRAFILM_BLUR_BACKEND", options.blurBackend.c_str(), 1);
    setenv("SPEKTRAFILM_BLUR_DOWNSAMPLE", options.blurDownsample.c_str(), 1);
    setenv("SPEKTRAFILM_INTERMEDIATE_PRECISION", options.intermediatePrecision.c_str(), 1);
    setenv("SPEKTRAFILM_DIFFUSION_CLUSTER_SIGMA", options.diffusionClusterSigma.c_str(), 1);
    setenv("SPEKTRAFILM_HALATION_GROUPED_TAIL", options.halationGroupedTail.c_str(), 1);
    setenv("SPEKTRAFILM_SCANNER_MPS", options.scannerMps.c_str(), 1);
    setenv("SPEKTRAFILM_GRAIN_BLUR_RECURRENCE", options.grainBlurRecurrence.c_str(), 1);
    setenv("SPEKTRAFILM_DIR_TAIL_BACKEND", options.dirTailBackend.c_str(), 1);
    setenv("SPEKTRAFILM_DENSITY_CURVE_LOOKUP", options.densityCurveLookup.c_str(), 1);
    setenv("SPEKTRAFILM_SPECTRAL_TRANSMITTANCE", options.spectralTransmittance.c_str(), 1);
    setenv("SPEKTRAFILM_PASS_TIMING", options.passTiming.c_str(), 1);
    setenv("SPEKTRAFILM_GRAIN_SYNTHESIS_SAMPLER", options.grainSynthesisSampler.c_str(), 1);
    setenv("SPEKTRAFILM_GRAIN_SYNTHESIS_RADIUS_LUT", options.grainSynthesisRadiusLut.c_str(), 1);
    setenv("SPEKTRAFILM_GRAIN_SYNTHESIS_TARGET_STORAGE", options.grainSynthesisTargetStorage.c_str(), 1);
    setenv("SPEKTRAFILM_GRAIN_SYNTHESIS_CELL_MODE", options.grainSynthesisCellMode.c_str(), 1);
    if (options.passTiming != "off") {
      setenv("SPEKTRAFILM_PASS_COUNTERS", "1", 1);
    }

    const std::vector<std::string> cases = selectedCases(options.caseName);
    if (cases.empty()) {
      std::cerr << "Unknown perf case: " << options.caseName << "\n";
      printUsage(argv[0]);
      return 2;
    }

    spektrafilm::MetalRenderer renderer;
    if (!renderer.isAvailable()) {
      std::cerr << "Metal renderer unavailable: " << renderer.lastError() << "\n";
      return 1;
    }

    spektrafilm_harness::HostPixelFormat sourceFormat;
    spektrafilm_harness::HostPixelFormat destinationFormat;
    spektrafilm_harness::HostLayout hostLayout;
    if (!spektrafilm_harness::parseHostPixelFormat(options.sourceFormat, sourceFormat) ||
        !spektrafilm_harness::parseHostPixelFormat(options.destinationFormat, destinationFormat) ||
        !spektrafilm_harness::parseHostLayout(options.hostLayout, hostLayout)) {
      std::cerr << "Invalid host I/O configuration.\n";
      return 2;
    }
    std::vector<float> sourcePixels = makeSyntheticFrame(options.width, options.height);
    spektrafilm_harness::HostRgbaBuffer source = spektrafilm_harness::makeSourceHostRgba(
      sourcePixels,
      options.width,
      options.height,
      sourceFormat,
      hostLayout
    );
    spektrafilm_harness::HostRgbaBuffer destination = spektrafilm_harness::makeDestinationHostRgba(
      options.width,
      options.height,
      destinationFormat,
      hostLayout
    );
    const spektrafilm::ImageView sourceView = spektrafilm_harness::imageView(source);
    spektrafilm::MutableImageView destinationView = spektrafilm_harness::mutableImageView(destination);
    const spektrafilm::RenderWindow window = spektrafilm_harness::renderWindowForLayout(hostLayout, options.width, options.height);

    std::cout
      << "case,width,height,iterations,avg_wall_ms,avg_fps,avg_cpu_setup_ms,avg_source_copy_ms,"
      << "avg_command_buffer_ms,avg_output_copy_ms,avg_pass_count,avg_static_alloc_bytes,"
      << "avg_static_alloc_count,avg_scratch_alloc_bytes,avg_scratch_alloc_count,"
      << "avg_shared_scratch_alloc_bytes,avg_shared_scratch_alloc_count,"
      << "avg_private_scratch_alloc_bytes,avg_private_scratch_alloc_count,avg_upload_bytes,"
      << "source_no_copy,destination_no_copy,private_scratch,pass_gpu_timing,pass_timing_mode,threadgroup,diffusion_group_size,"
      << "scanner_image_storage,blur_backend,blur_downsample,intermediate_precision,diffusion_cluster_sigma,halation_grouped_tail,"
      << "scanner_mps,grain_blur_recurrence,dir_tail_backend,density_curve_lookup,spectral_transmittance,source_format,destination_format,host_layout,grain_synthesis_sampler,grain_synthesis_radius_lut,grain_synthesis_target_storage,"
      << "grain_synthesis_cell_mode,halation,camera_diffusion,print_diffusion,dir,production_grain,final_post_process,mean_luma\n";
    std::vector<std::string> detailRows;

    for (const std::string &caseName : cases) {
      spektrafilm::RenderParams params = paramsForCase(caseName);
      if (options.grainSynthesisSamples > 0) {
        params.grainSynthesisSamples = options.grainSynthesisSamples;
      }
      if (options.grainSynthesisLayeredOverride) {
        params.grainSynthesisLayered = options.grainSynthesisLayered;
      }
      if (options.grainSynthesisRadiusStdDevOverride) {
        params.grainSynthesisRadiusStdDevRatio = options.grainSynthesisRadiusStdDev;
      }
      if (options.grainSynthesisObservationSigmaOverride) {
        params.grainSynthesisObservationSigmaUm = options.grainSynthesisObservationSigmaUm;
      }

      for (int i = 0; i < options.warmup; ++i) {
        if (!renderer.render(sourceView, destinationView, window, params, static_cast<double>(i))) {
          std::cerr << "Warmup render failed for " << caseName << ": " << renderer.lastError() << "\n";
          return 1;
        }
      }

      double wallMs = 0.0;
      double cpuSetupMs = 0.0;
      double sourceCopyMs = 0.0;
      double commandBufferMs = 0.0;
      double outputCopyMs = 0.0;
      double passCount = 0.0;
      double staticAllocationBytes = 0.0;
      double staticAllocationCount = 0.0;
      double scratchAllocationBytes = 0.0;
      double scratchAllocationCount = 0.0;
      double sharedScratchAllocationBytes = 0.0;
      double sharedScratchAllocationCount = 0.0;
      double privateScratchAllocationBytes = 0.0;
      double privateScratchAllocationCount = 0.0;
      double uploadBytes = 0.0;
      bool sourceNoCopy = false;
      bool destinationNoCopy = false;
      bool privateScratch = false;
      bool passGpuTiming = false;
      std::string passTimingMode = "off";
      bool halation = false;
      bool cameraDiffusion = false;
      bool printDiffusion = false;
      bool dir = false;
      bool productionGrain = false;
      bool finalPostProcess = false;
      bool scannerTextureIntermediates = false;
      bool halationGroupedTail = false;
      bool scannerMps = false;
      bool grainBlurRecurrence = false;
      uint32_t diffusionGroupSize = 2u;
      std::string threadgroupMode = "auto";
      std::string blurBackend = "custom";
      std::string blurDownsample = "auto";
      std::string intermediatePrecision = "float";
      std::string diffusionClusterSigma = "0.10";
      std::string dirTailBackend = "mps";
      std::string densityCurveLookup = "binary";
      std::string spectralTransmittance = "pow";

      for (int i = 0; i < options.iterations; ++i) {
        const auto start = Clock::now();
        if (!renderer.render(sourceView, destinationView, window, params, static_cast<double>(i))) {
          std::cerr << "Render failed for " << caseName << ": " << renderer.lastError() << "\n";
          return 1;
        }
        wallMs += elapsedMs(start, Clock::now());
        const spektrafilm::MetalRenderDiagnostics &diag = renderer.lastDiagnostics();
        cpuSetupMs += diag.cpuSetupMs;
        sourceCopyMs += diag.sourceCopyMs;
        commandBufferMs += diag.commandBufferMs;
        outputCopyMs += diag.outputCopyMs;
        passCount += diag.passCount;
        staticAllocationBytes += static_cast<double>(diag.staticAllocationBytes);
        staticAllocationCount += static_cast<double>(diag.staticAllocationCount);
        scratchAllocationBytes += static_cast<double>(diag.scratchAllocationBytes);
        scratchAllocationCount += static_cast<double>(diag.scratchAllocationCount);
        sharedScratchAllocationBytes += static_cast<double>(diag.sharedScratchAllocationBytes);
        sharedScratchAllocationCount += static_cast<double>(diag.sharedScratchAllocationCount);
        privateScratchAllocationBytes += static_cast<double>(diag.privateScratchAllocationBytes);
        privateScratchAllocationCount += static_cast<double>(diag.privateScratchAllocationCount);
        uploadBytes += static_cast<double>(diag.uploadBytes);
        sourceNoCopy = diag.sourceNoCopy;
        destinationNoCopy = diag.destinationNoCopy;
        privateScratch = diag.privateScratchEnabled;
        passGpuTiming = diag.passGpuTimingAvailable;
        passTimingMode = diag.passTimingMode;
        halation = diag.halationPath;
        cameraDiffusion = diag.cameraDiffusionPath;
        printDiffusion = diag.printDiffusionPath;
        dir = diag.dirPath;
        productionGrain = diag.productionGrainPath;
        finalPostProcess = diag.finalPostProcessPath;
        scannerTextureIntermediates = diag.scannerTextureIntermediates;
        halationGroupedTail = diag.halationGroupedTail;
        scannerMps = diag.scannerMps;
        grainBlurRecurrence = diag.grainBlurRecurrence;
        diffusionGroupSize = diag.diffusionGroupSize;
        threadgroupMode = diag.threadgroupMode;
        blurBackend = diag.blurBackend.empty() ? options.blurBackend : diag.blurBackend;
        blurDownsample = diag.blurDownsample.empty() ? options.blurDownsample : diag.blurDownsample;
        intermediatePrecision = diag.intermediatePrecision.empty() ? options.intermediatePrecision : diag.intermediatePrecision;
        diffusionClusterSigma = diag.diffusionClusterSigma.empty() ? options.diffusionClusterSigma : diag.diffusionClusterSigma;
        dirTailBackend = diag.dirTailBackend.empty() ? options.dirTailBackend : diag.dirTailBackend;
        densityCurveLookup = diag.densityCurveLookup.empty() ? options.densityCurveLookup : diag.densityCurveLookup;
        spectralTransmittance = diag.spectralTransmittance.empty() ? options.spectralTransmittance : diag.spectralTransmittance;
        if (options.detail) {
          for (size_t passIndex = 0; passIndex < diag.passes.size(); ++passIndex) {
            const spektrafilm::MetalPassDiagnostics &pass = diag.passes[passIndex];
            std::ostringstream row;
            row << caseName << ','
                << i << ','
                << passIndex << ','
                << pass.name << ','
                << pass.gpuMs << ','
                << (pass.gpuTimeAvailable ? 1 : 0) << ','
                << diag.passTimingMode << ','
                << pass.width << ','
                << pass.height << ','
                << pass.depth << ','
                << pass.threadgroupWidth << ','
                << pass.threadgroupHeight << ','
                << pass.estimatedBytes;
            detailRows.push_back(row.str());
          }
        }
      }

      const double denom = std::max(options.iterations, 1);
      const double avgWallMs = wallMs / denom;
      const double avgFps = avgWallMs > 0.0 ? 1000.0 / avgWallMs : 0.0;
      std::cout << std::fixed << std::setprecision(3)
                << caseName << ','
                << options.width << ','
                << options.height << ','
                << options.iterations << ','
                << avgWallMs << ','
                << avgFps << ','
                << cpuSetupMs / denom << ','
                << sourceCopyMs / denom << ','
                << commandBufferMs / denom << ','
                << outputCopyMs / denom << ','
                << passCount / denom << ','
                << staticAllocationBytes / denom << ','
                << staticAllocationCount / denom << ','
                << scratchAllocationBytes / denom << ','
                << scratchAllocationCount / denom << ','
                << sharedScratchAllocationBytes / denom << ','
                << sharedScratchAllocationCount / denom << ','
                << privateScratchAllocationBytes / denom << ','
                << privateScratchAllocationCount / denom << ','
                << uploadBytes / denom << ','
                << (sourceNoCopy ? 1 : 0) << ','
                << (destinationNoCopy ? 1 : 0) << ','
                << (privateScratch ? 1 : 0) << ','
                << (passGpuTiming ? 1 : 0) << ','
                << passTimingMode << ','
                << threadgroupMode << ','
                << diffusionGroupSize << ','
                << (scannerTextureIntermediates ? "texture" : "buffer") << ','
                << blurBackend << ','
                << blurDownsample << ','
                << intermediatePrecision << ','
                << diffusionClusterSigma << ','
                << (halationGroupedTail ? 1 : 0) << ','
                << (scannerMps ? 1 : 0) << ','
                << (grainBlurRecurrence ? 1 : 0) << ','
                << dirTailBackend << ','
                << densityCurveLookup << ','
                << spectralTransmittance << ','
                << options.sourceFormat << ','
                << options.destinationFormat << ','
                << options.hostLayout << ','
                << options.grainSynthesisSampler << ','
                << options.grainSynthesisRadiusLut << ','
                << options.grainSynthesisTargetStorage << ','
                << options.grainSynthesisCellMode << ','
                << (halation ? 1 : 0) << ','
                << (cameraDiffusion ? 1 : 0) << ','
                << (printDiffusion ? 1 : 0) << ','
                << (dir ? 1 : 0) << ','
                << (productionGrain ? 1 : 0) << ','
                << (finalPostProcess ? 1 : 0) << ','
                << spektrafilm_harness::averageWindowLuma(destination)
                << '\n';
    }
    if (options.detail) {
      std::cout
        << "# pass_detail\n"
        << "detail_case,iteration,pass_index,name,gpu_ms,gpu_time_available,timing_mode,width,height,depth,"
        << "threadgroup_width,threadgroup_height,estimated_bytes\n";
      for (const std::string &row : detailRows) {
        std::cout << row << '\n';
      }
    }
  }
  return 0;
}
