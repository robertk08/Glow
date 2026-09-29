#include "Outlet.h"

#include <errno.h>
#include <lwip/api.h>
#include <lwip/sockets.h>
#include <lwip/tcp.h>
#include <lwip/tcpip.h>

extern "C" {
#include <lwip/priv/sockets_priv.h>
}

size_t Outlet::write(const uint8_t *data, size_t size) {
  int socket = fd();
  if (socket < 0 || !connected()) return 0;

  size_t   sent  = 0;
  uint32_t since = millis();

  while (sent < size) {
    int n = send(socket, data + sent, size - sent, MSG_DONTWAIT);
    if (n > 0) {
      sent += (size_t)n;
      since = millis();
      continue;
    }
    if ((n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) || millis() - since >= patience) {
      stop();
      break;
    }

    fd_set writable;
    FD_ZERO(&writable);
    FD_SET(socket, &writable);
    timeval wait = {0, 10000};
    select(socket + 1, nullptr, &writable, nullptr, &wait);
  }

  return sent;
}

size_t Outlet::queued() {
  int socket = fd();
  if (socket < 0) return 0;

  LOCK_TCPIP_CORE();
  lwip_sock *sock   = lwip_socket_dbg_get_socket(socket);
  size_t     queued = sock && sock->conn && sock->conn->pcb.tcp ? sock->conn->pcb.tcp->snd_queuelen : 0;
  UNLOCK_TCPIP_CORE();
  return queued;
}
