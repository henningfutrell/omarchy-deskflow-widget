# Deskflow for the Omarchy bar

A native [Omarchy](https://omarchy.org) bar widget for [Deskflow](https://github.com/deskflow/deskflow)
keyboard and mouse sharing. It uses the theme's own font, colours and panel
components, so it looks and behaves like the built-in Bluetooth or Tailscale
widgets.

- Bar icon is lit while connected, dimmed while stopped, and turns the urgent
  colour on errors
- Left click opens a keyboard-friendly panel; right click toggles Deskflow
- On/off switch, start-on-login toggle, and a shortcut to Deskflow's settings
- **Client mode** shows the server you're connected to
- **Server mode** lists the connected clients

## Install

```sh
omarchy pkg add deskflow
omarchy plugin add https://github.com/henningfutrell/omarchy-deskflow-widget.git --enable
omarchy bar move deskflow --before omarchy.bluetooth
```

On the server, also switch the widget to server mode:

```sh
omarchy bar set deskflow mode server
```

The widget runs Deskflow as the systemd user unit `deskflow@client` or
`deskflow@server`. It installs that unit from this repo the first time you
switch it on.

## First-time setup

Click the widget and choose **Pair / settings**. This opens the Deskflow app,
where you:

- **Server:** add each client's screen name (its hostname) to the layout, and
  allow the port with `sudo ufw allow 24800/tcp`.
- **Client:** enter the server's address and accept its fingerprint.

Close the app afterwards and use the widget's switch.

## Clients on Hyprland need a RemoteDesktop portal

A Deskflow **client** receives input through the
`org.freedesktop.portal.RemoteDesktop` portal. Hyprland's portal
(xdg-desktop-portal-hyprland 1.4) doesn't provide it, so a client connects but
the cursor never moves. The server only needs InputCapture and works as is.

On clients, install the
[hypr-kdeconnect-fix](https://github.com/gfhdhytghd/hypr-kdeconnect-fix) bridge
and route RemoteDesktop to it:

```sh
omarchy pkg aur add hypr-kdeconnect-fix-git
mkdir -p ~/.config/xdg-desktop-portal
printf '[preferred]\ndefault=hyprland;gtk\norg.freedesktop.impl.portal.RemoteDesktop=hypr-kdeconnect\n' \
  > ~/.config/xdg-desktop-portal/hyprland-portals.conf
systemctl --user restart xdg-desktop-portal.service hypr-kdeconnect-portal.service
```

If you already have a `~/.config/xdg-desktop-portal/hyprland-portals.conf`,
add only the `RemoteDesktop=` line to it instead.

If the widget shows **Input bridge unavailable**, check that
`hypr-kdeconnect-portal.service` is running:

```sh
journalctl --user -u hypr-kdeconnect-portal
```

## Keyboard shortcuts

In the panel:

| Key | Action |
| --- | --- |
| `j` / `k` or arrows | Move the cursor |
| `enter` / `space` | Activate the current row |
| `t` | Toggle Deskflow |
| `a` | Toggle start on login |
| `s` | Open Deskflow settings |
| `r` | Refresh |
| `esc` | Close |

## Settings

| Key | Values | Default |
| --- | --- | --- |
| `mode` | `client`, `server` | `client` |
| `refreshIntervalSec` | 2–300 | 5 |
