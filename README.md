# Deskflow for the Omarchy bar

A native [Omarchy](https://omarchy.org) bar widget for
[Deskflow](https://github.com/deskflow/deskflow) keyboard and mouse sharing.
You set everything up from the widget, so you never have to open the Deskflow
app. It uses the theme's own font, colours and panel components, so it looks
and behaves like the built-in Bluetooth or Tailscale widgets.

- The bar icon is lit while connected, dimmed while stopped, and turns the
  urgent colour on errors
- Left click opens the panel; right click turns Deskflow on or off
- **Client:** enter the server's address
- **Server:** place each client above, below, left or right, and remove it again
- **Pairing:** trust the other machine after comparing fingerprints
- Share the clipboard, switch between client and server, and start on login

## Install

```sh
omarchy pkg add deskflow
omarchy plugin add https://github.com/henningfutrell/omarchy-deskflow-widget.git --enable --yes
omarchy bar move deskflow --before omarchy.bluetooth
```

## Setup

1. **Server** (the machine whose keyboard and mouse you'll use): open the
   widget, choose **Switch to server**, and turn it on. Allow the port with
   `sudo ufw allow 24800/tcp`.
2. **Client:** open the widget, type the server's name or IP into **Server**,
   press Enter, and turn it on.
3. The server's fingerprint appears in the client's panel. Check that it matches
   the **This machine** fingerprint in the server's panel, then choose **Trust
   this server**.
4. The server's panel now shows the client's fingerprint. Check it against the
   client's **This machine** fingerprint and choose **Trust this client**.
5. The server then asks where the client sits. Pick **Above**, **Below**,
   **Left** or **Right**.
6. To copy on one machine and paste on the other, turn on **Share clipboard**
   on both.

To change a client's position later, remove it from **Clients** with its
trash icon (or `x`). It reappears the next time that client connects.

The widget runs Deskflow as the systemd user unit `deskflow@client` or
`deskflow@server`. It installs that unit from this repo the first time you
switch it on. If the Deskflow app is open, the widget closes it before starting,
because the app runs its own copy of Deskflow and the two would fight over the
connection.

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

The bridge recognises Deskflow by reading `/proc/<pid>/exe`, but its default
sandbox stops it from doing that. Without the override below, it refuses every
session with `refusing RemoteDesktop session for app id ""`: the client connects
and the cursor reaches its screen, but no input arrives. The override turns off
that part of the sandbox for the bridge only. The bridge still accepts only
`deskflow-core` and KDE Connect. (Fix from
[omarchy-deskflow-kvm](https://github.com/hermany/omarchy-deskflow-kvm).)

```sh
mkdir -p ~/.config/systemd/user/hypr-kdeconnect-portal.service.d
printf '[Service]\nPrivateTmp=no\nProtectSystem=no\nProtectHome=no\n' \
  > ~/.config/systemd/user/hypr-kdeconnect-portal.service.d/override.conf
systemctl --user daemon-reload
systemctl --user restart hypr-kdeconnect-portal.service
```

If the client connects but no input arrives, check the bridge's log. You
should see `allowing RemoteDesktop session … /usr/bin/deskflow-core`:

```sh
journalctl --user -u hypr-kdeconnect-portal
```

## Files

The widget writes the same files the Deskflow app would, using `deskflowctl` in
this repo:

| File | Contents |
| --- | --- |
| `~/.config/Deskflow/Deskflow.conf` | Server address |
| `~/.config/Deskflow/deskflow-server.conf` | Server screen layout, generated |
| `~/.config/Deskflow/omarchy-screens` | The widget's list of placed clients |
| `~/.config/Deskflow/tls/deskflow.pem` | This machine's certificate, created on first start |
| `~/.config/Deskflow/tls/trusted-servers` | Servers this client trusts |
| `~/.config/Deskflow/tls/trusted-clients` | Clients this server trusts |

## Keyboard shortcuts

In the panel:

| Key | Action |
| --- | --- |
| `j` / `k` or arrows | Move the cursor (`h` / `l` picks a side) |
| `enter` / `space` | Activate the current row |
| `x` / `delete` | Remove the selected client |
| `t` | Turn Deskflow on or off |
| `m` | Switch between client and server |
| `c` | Toggle clipboard sharing |
| `a` | Toggle start on login |
| `r` | Refresh |
| `esc` | Close |

## Settings

| Key | Values | Default |
| --- | --- | --- |
| `mode` | `auto`, `client`, `server` | `auto` (follows the Deskflow app's last mode) |
| `refreshIntervalSec` | 2–300 | 5 |
