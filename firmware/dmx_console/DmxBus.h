#pragma once
//  ============================================================================
//  DmxBus - owns the 513-byte universe and the esp_dmx driver.
//  Knows nothing about fixtures. Every slot write is bounds-checked here.
//
//  The frame is clocked onto the wire by a task of its own, not from loop().
//  A WebSocket read blocks for seconds when WiFi stalls, and a fixture that
//  stops hearing DMX for about a second blacks out by itself - so the wire and
//  the network must not share a thread.
//  ============================================================================
#include "Config.h"

namespace DmxBus {

// Slot 0 is the start code; usable slots are 1..512.
static const int SLOT_MIN = 1;
static const int SLOT_MAX = DMX_PACKET_SIZE - 1;   // 512

bool begin();          // install driver, route the pin, start the refresh task

// ----------------------------------------------------------------- writers --
// Three things write the universe and none of them knows about the others:
//
//   the serial console  ->  Fixture::set*()  ->  setSlot()
//   the iOS app         ->  Link             ->  writeRange()
//   HomeSpan, stage 2   ->  Fixture::set*()  ->  setSlot()
//
// Last writer wins, per slot, until the next one comes along. That is fine
// today: the console is a debugging tool nobody uses while the app is driving.
//
// It stops being fine in stage 2. The app owns the whole universe and re-sends
// it continuously, so a HomeKit brightness change written into the dimmer slot
// survives exactly one frame before the app's next update paints over it - and
// from the Home app that looks like the slider springing back on its own.
// Arbitration is the real work there: either a slot has an owner, or HomeKit
// changes travel to the app as state and come back down as DMX like everything
// else. Both are decisions for stage 2. This layer cannot guess which.

bool setSlot(int slot, uint8_t value);   // false if out of range
int  getSlot(int slot);                  // -1 if out of range

// PROTOCOL.md's binary opcode 0x01 lands here: 1-based start, length bytes.
bool writeRange(int start, const uint8_t *values, int length);

void clear();

// ------------------------------------------------------------------ output --

bool setRefreshHz(int hz);   // false outside DMX_REFRESH_HZ_MIN..MAX
int  refreshHz();

// Blackout zeroes what goes out without touching what is held, so the look
// comes back intact when it is switched off again.
void setBlackout(bool on);
bool blackout();

void identify();             // flash the output for a moment, then carry on

}  // namespace DmxBus
