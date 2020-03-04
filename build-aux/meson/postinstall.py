#!/usr/bin/env python3

from os import environ, path
from shutil import copy
from subprocess import call

prefix = environ.get('MESON_INSTALL_PREFIX', '/usr/local')
bindir = path.join(prefix, 'bin')
datadir = path.join(prefix, 'share')
destdir = environ.get('DESTDIR', '')
schema_dir = path.join(datadir, 'glib-2.0', 'schemas')

# Package managers set this so we don't need to run
if not destdir:
    print('Updating icon cache...')
    call(['gtk-update-icon-cache', '-qtf', path.join(datadir, 'icons', 'hicolor')])

    print('Updating desktop database...')
    call(['update-desktop-database', '-q', path.join(datadir, 'applications')])

    print('Compiling GSettings schemas...')
    call(['glib-compile-schemas', schema_dir])
    copy(path.join(schema_dir, 'gschemas.compiled'), bindir)

