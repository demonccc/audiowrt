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

MIDI is intentionally outside the constrained baseline. A usable MIDI feature would require a synthesizer, sound bank or a complete USB/BLE routing workflow; transport support alone does not provide an end-user capability and does not justify its flash cost.

Local USB storage and extroot are not part of the mandatory 8 MB core. They
remain available in the `standard` and `full` flavors; the storage CLI,
filesystem/USB dependencies and LuCI page are absent from `minimal`.

## Mandatory output/music baseline

The reference build must attempt to include:

- Bluetooth A2DP Source output for speakers and headphones.
- USB Audio Class output for USB DACs and sound cards.

Bluetooth is an output/music capability, not an AudioWRT Extension.

The first WDR4300 build with the generic OpenWrt BlueZ/SBC dependency chain reached `9,939,466` bytes against the device image limit of `7,861,804` bytes: an overage of `2,077,662` bytes (about 1.98 MiB). Storage was already absent from that measurement, so the result isolated Bluetooth as the next size problem.

The 8 MB baseline therefore uses an AudioWRT-specific minimal Bluetooth stack instead of dropping Bluetooth:

- a minimal BlueZ `bluetoothd` with classic A2DP/AVRCP retained while MIDI, unrelated profiles, tools, monitor, OBEX and the generic CLI are disabled;
- an AudioWRT-owned `libbluetooth` built from the same minimal BlueZ source;
- a library-only SBC package without `libsndfile` or SBC command-line tools;
- BlueALSA restricted to the A2DP Source/SBC path;
- a compact AudioWRT D-Bus controller for discovery, pairing and connection instead of `bluetoothctl`/`hciconfig`.

The minimized stack compiled end-to-end on the WDR4300 SDK with Bluetooth MIDI, SBC, BlueALSA and the compact D-Bus controller. That historical measurement produced a `5,763.81 KiB` SquashFS root filesystem but still exceeded the TP-Link firmware limit by `780,394` bytes (about 762 KiB). MIDI has since been removed; the next build is authoritative for the new size.

The next size pass keeps the explicitly requested generic LuCI pages for Status, System and Package Manager, but does not preinstall `luci-mod-network`. Network configuration is an AudioWRT-owned product flow: the dedicated Wi-Fi Client UI handles SSID/AP selection and IPv4 configuration directly. This avoids carrying the generic network UI while preserving the appliance administration pages that are intentionally part of the product.

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
- IPv4 configuration is part of the AudioWRT Wi-Fi flow: users can select automatic DHCP or manual IPv4 configuration.
- Manual IPv4 requires address, netmask and default gateway; DNS servers are configurable explicitly.

The provisioning wizard and the normal Wi-Fi Client UI must expose the same user model: grouped SSIDs, available bands, channel/signal information, access-point count, an expandable BSSID list, and the same DHCP/manual IPv4 controls.

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
  -> MIDI is omitted until AudioWRT can provide a complete synthesizer or routing feature
```

The Bluetooth minimization is a size-driven implementation step toward this acceptance path. DLNA remains the next network-input milestone after the output baseline produces a valid WDR4300 firmware.
