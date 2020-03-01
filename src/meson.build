bxt_launcher_sources = [
  'main.vala',
  'process.vala',
  'system-monitor.vala',
  'window.vala',
]

bxt_launcher_deps = [
  dependency('gio-2.0', version: '>= 2.48'),
  dependency('gtk+-3.0', version: '>= 3.18'),
  dependency('gee-0.8', version: '>= 0.18'),
  dependency('libgtop-2.0', version: '>= 2.32'),
  valac.find_library('posix'),
]

gnome = import('gnome')

bxt_launcher_sources += gnome.compile_resources('bxt_launcher-resources',
  'bxt_launcher.gresource.xml',
  c_name: 'bxt_launcher'
)

vala_args = [
  '--target-glib=2.48',
  '--vapidir=' + vapi_dir,
]

executable('bxt-launcher', bxt_launcher_sources,
  vala_args: vala_args, dependencies: bxt_launcher_deps,
  install: true,
)
