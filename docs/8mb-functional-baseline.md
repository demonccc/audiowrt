# AudioWRT 8 MB Functional Baseline

The TP-Link TL-WDR4300 v1 is the reference low-end target for AudioWRT. The purpose of the baseline is not to enable every AudioWRT feature on 8 MB flash, but to guarantee a useful network-audio endpoint on constrained hardware.

## Product direction

AudioWRT is primarily a network audio endpoint. Network protocols provide audio to the device and AudioWRT routes it to one of the supported physical outputs.

```text
Network audio receiver
        |
        v
   AudioWRT output
      /      \
Bluetooth    USB Audio
A2DP Source  USB DAC
```

Bluetooth MIDI is part of the current constrained-baseline experiment, not a deferred feature. It does not carry audio samples; BlueZ exposes Bluetooth MIDI events through ALSA Sequencer so controllers/instruments can participate in AudioWRT music-routing use cases without requiring the general-purpose BlueZ tool stack.

Local USB storage and extroot are not part of the mandatory 8 MB core. They remain useful for larger installations and optional services. A build that wants the guided external-storage stack must request it explicitly with `FEATURES=storage`; the storage CLI, filesystem/USB dependencies and LuCI page are otherwise absent from the baseline.

## Mandatory output/music baseline

The reference build must attempt to include:

- Bluetooth A2DP Source output for speakers and headphones.
- Bluetooth MIDI via ALSA Sequencer.
- USB Audio Class output for USB DACs and sound cards.

Bluetooth is an output/music capability, not an AudioWRT Extension.

The first WDR4300 build with the generic OpenWrt BlueZ/SBC dependency chain reached `9,939,466` bytes against the device image limit of `7,861,804` bytes: an overage of `2,077,662` bytes (about 1.98 MiB). Storage was already absent from that measurement, so the result isolated Bluetooth as the next size problem.

The 8 MB baseline therefore uses an AudioWRT-specific minimal Bluetooth stack instead of dropping Bluetooth:

- a minimal BlueZ `bluetoothd` with classic A2DP/AVRCP and Bluetooth MIDI retained while unrelated profiles, tools, monitor, OBEX and the generic CLI are disabled;
- an AudioWRT-owned `libbluetooth` built from the same minimal BlueZ source;
- a library-only SBC package without `libsndfile` or SBC command-line tools;
- BlueALSA restricted to the A2DP Source/SBC path;
- a compact AudioWRT D-Bus controller for discovery, pairing and connection instead of `bluetoothctl`/`hciconfig`.

Bluetooth MIDI is intentionally enabled before the next size measurement. The next WDR4300 ImageBuilder result therefore measures the cost of the minimized A2DP/AVRCP + Bluetooth MIDI + USB Audio baseline together. If it fits, MIDI remains in the baseline; if it does not, the measured delta becomes part of the next size decision rather than an assumption made in advance.

This removes the generic dependency chains through `bluez-utils`, readline/ncurses, libical, libsndfile, LAME and mpg123. The firmware build remains authoritative: these changes are not considered sufficient for the 8 MB target until ImageBuilder produces valid WDR4300 images and the resulting size is measured.

## Network input baseline

The first network input target is a lightweight audio-only DLNA/UPnP MediaRenderer. This enables Home Assistant / Music Assistant and other UPnP controllers to send audio to AudioWRT without requiring Spotify Connect, local storage or a full media framework on the router.

AirPlay is the next receiver candidate after the DLNA baseline is measured. Spotify Connect remains optional because its runtime/package footprint is substantially larger on constrained devices.

## Provisioning rules

Provisioning must work on both single-radio and multi-radio devices and must never depend on concurrent AP+STA support on one PHY.

- If the target STA radio differs from the setup AP radio, keep the setup AP while connecting.
- If the target STA uses the setup radio and another radio exists, move the setup AP to the alternate radio first.
- If only one radio exists, stop the setup AP, switch to STA, and restore the setup AP after timeout if association/DHCP fails.
- Selecting an SSID does not pin a BSSID by default, allowing normal roaming on the selected radio.
- Selecting a specific access point explicitly stores its BSSID.

The provisioning wizard and the normal Wi-Fi Client UI must expose the same user model: grouped SSIDs, available bands, channel/signal information, access-point count, and an expandable BSSID list.

## Extension semantics

Extensions are optional audio services, not hardware outputs. The UI must report package state from configured APK repositories:

- `installed`: package is installed.
- `installable`: package is available from a configured repository.
- `unavailable`: package is neither installed nor currently available.

The UI must not display an Install action for unavailable packages.

## Reference acceptance path

The final 8 MB functional milestone is:

```text
fresh flash
  -> provision Wi-Fi/Ethernet
  -> network controller discovers AudioWRT
  -> controller starts playback
  -> AudioWRT routes audio to Bluetooth A2DP Source
  -> optionally switch to a USB Audio Class DAC
  -> Bluetooth MIDI remains available through ALSA Sequencer
```

The Bluetooth minimization is a size-driven implementation step toward this acceptance path. DLNA remains the next network-input milestone after the output baseline produces a valid WDR4300 firmware.
