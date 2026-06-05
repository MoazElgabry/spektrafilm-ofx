#include "SpektraRenderer.h"
#include "SpektraCudaRenderer.h"
#include "SpektraVulkanRenderer.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <string>

namespace spektrafilm {

std::unique_ptr<Renderer> createNativeRenderer() {
  std::string requested = "auto";
  if (const char *value = std::getenv("SPEKTRAFILM_WINDOWS_BACKEND"); value && *value) {
    requested = value;
    std::transform(requested.begin(), requested.end(), requested.begin(), [](unsigned char ch) {
      return static_cast<char>(std::tolower(ch));
    });
  }

  if (requested == "vulkan") {
    return createVulkanRenderer();
  }

  // keep the fast path first; Vulkan stays around as the compatibility backend
  std::unique_ptr<Renderer> cuda = createCudaRenderer();
  if (requested == "cuda" || (cuda && cuda->isAvailable())) {
    return cuda;
  }

  return createVulkanRenderer();
}

} // namespace spektrafilm
