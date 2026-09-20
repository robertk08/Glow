#pragma once
#include "DmxBus.h"

namespace Flash {

template <typename Fn>
bool guarded(Fn write) {
  DmxBus::pause();
  bool ok = write();
  DmxBus::resume();
  return ok;
}

}  // namespace Flash
