# AudioWRT 8 MB Functional Baseline

The TP-Link TL-WDR4300 v1 is the reference constrained target for AudioWRT. The objective is not to carry every AudioWRT feature on 8 MB flash; it is to preserve a useful network-audio appliance with predictable provisioning, administration and playback.

## Product baseline

The constrained device remains a network-audio endpoint:

```text
network controller
      |
      v
AudioWRT DLNA Renderer
      |
      v
AudioWRT output
   /        \
Bluetooth  USB Audio
A2DP       USB DAC
```

MIDI, local media-library features and large optional receivers are outside the mandatory 8 MB baseline.

## Current constrained profiles

The WDR4300 is intentionally split into separate constrained profiles instead of forcing every physical output into one image:

- `tplink-tl-wdr4300-v1-minimal-usb-bluetooth-25.12.5`
- `tplink-tl-wdr4300-v1-minimal-usb-audio-25.12.5`

The Bluetooth profile is the current reference for the minimized Bluetooth runtime. The USB Audio profile provides the smaller USB-DAC path.

Package composition is driven by package groups under `config/package-groups/`, not by the historical flavor model.

## Constrained runtime policy

The minimal runtime uses AudioWRT-owned replacements only when the compiled feature set or footprint genuinely needs to differ from standard OpenWrt.

The current policy includes:

- `audiowrt-busybox` with unused applets removed while retaining practical diagnostics such as `vi`, `top` and `which`;
- `audiowrt-wpad` for the required Wi-Fi station/setup paths without carrying the full generic hostap feature set;
- `audiowrt-dropbear` as the constrained SSH server;
- minimized ALSA runtime;
- minimized Bluetooth/BlueALSA stack for A2DP Source;
- native lightweight codec players;
- no MIDI support;
- no separate `umdns` daemon in the default renderer path.

The `minimal-usb-bluetooth` capability group removes heavier MP3/AAC/M4A player packages from the shared minimal set to reduce flash pressure further.

The firmware build remains authoritative for fit. Package intent is not considered sufficient until ImageBuilder produces a valid target image.

## Network renderer baseline

DLNA/UPnP MediaRenderer is the mandatory public network-audio path on the constrained image.

The AudioWRT renderer is native and lightweight. MPD and `upmpdcli` are not part of the default constrained renderer stack. Installed player packages register their codec/MIME capabilities, and the renderer advertises only formats that can actually be played.

This keeps Home Assistant / Music Assistant and other UPnP controllers usable without bringing a general media framework into the 8 MB baseline.

## Provisioning baseline

A fresh constrained image must be recoverable without assuming a router-style default network.

Factory state:

- hostname `AudioWRT`;
- LAN is a DHCP client;
- no `192.168.1.1` default LAN address;
- WAN disabled;
- no stock Wi-Fi SSID;
- radios disabled until runtime/provisioning needs them.

Provisioning checks connectivity in this order:

1. persistent Wi-Fi client has link + IP;
2. LAN has link + IP;
3. otherwise start the temporary setup network.

The temporary network uses:

```text
SSID: AudioWRT-<MAC suffix>
IPv4: 192.168.77.1/24
```

The setup AP must remain runtime-only. It must not leave temporary UCI Wi-Fi sections behind after provisioning finishes.

Selecting a Wi-Fi network normally stores the SSID and lets the station choose the best matching access point. The provisioning UI should not force users to understand or pin individual BSSIDs for a normal setup flow.

## Administration baseline

The constrained image retains the essential LuCI administration surface and the AudioWRT-owned pages required to operate the appliance.

The AudioWRT LuCI theme and provisioning wizard share the same visual language and branding so the device does not switch between unrelated interfaces after setup.

Generic pages that pull large dependency chains are avoided unless they provide enough operational value to justify their footprint.

## Audio output baseline

Bluetooth profile:

- classic Bluetooth stack required for A2DP Source;
- BlueALSA output path;
- saved/paired-device management through AudioWRT;
- firmware support may be included for validated USB Bluetooth adapters where needed.

USB Audio profile:

- USB Audio Class kernel/runtime support;
- ALSA route managed by AudioWRT;
- native players write PCM through the selected AudioWRT output.

The runtime always creates a valid AudioWRT ALSA configuration, even when no output device is currently selected, so player/renderer startup does not depend on a stale or missing device file.

## Storage and flash discipline

The WDR4300 has very little writable overlay headroom. Experimental package installs must not be used as a normal validation mechanism on this target.

During development:

- test replacement scripts/UI/assets from `/tmp` with bind mounts;
- avoid writing large temporary packages to overlay;
- treat ImageBuilder composition as the source of truth for the next firmware;
- measure the resulting SquashFS/rootfs-data boundary after each size-sensitive change.

This is particularly important because crossing a flash erase-block boundary can reduce writable overlay by an entire block even when the added compressed payload is small.

## Acceptance path

A constrained image is useful when this flow works:

```text
fresh flash
  -> obtain network through configured Wi-Fi or Ethernet
     OR expose temporary AudioWRT setup network
  -> provision hostname / Wi-Fi / administrator access
  -> network controller discovers DLNA Renderer
  -> controller starts playback
  -> AudioWRT routes decoded PCM to the selected physical output
  -> LuCI remains available with the AudioWRT theme for administration
```

The 8 MB baseline should optimize for this complete product path before optional services are added.
