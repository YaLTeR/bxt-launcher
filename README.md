# Bunnymod XT Launcher

A work-in-progress GUI launcher for Bunnymod XT.

## Building

You will need the Vala compiler and GTK libraries (GIO, GTK, libgtop, libgee).

```sh
meson build
ninja -C build
```

## Building for Development

The launcher expects to find its GSettings schema and `libBunnymodXT.so` alongside its binary.
Installing into a prefix without `DESTDIR` sets everything up:

```sh
meson -Dprefix=$PWD/install build
ninja -C build install
# Copy libBunnymodXT.so into install/bin/ manually.
# Then start the launcher:
install/bin/bxt-launcher
```
