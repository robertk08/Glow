#pragma once
#include <NetworkClient.h>

class Outlet : public NetworkClient {
 public:
  Outlet(int fd, uint32_t patience) : NetworkClient(fd), patience(patience) {}

  using NetworkClient::write;
  size_t write(const uint8_t *data, size_t size) override;

  uint32_t patience;
};
