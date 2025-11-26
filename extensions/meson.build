nautilus_sources = files('nautilus_extension.vala') + core_sources

shared_library('nautilus-app-manager',
  nautilus_sources,
  dependencies: [gio_dep, glib_dep, json_glib_dep, gee_dep, gtk_dep, nautilus_dep, libsoup_dep],
  vala_args: ['--vapidir=' + join_paths(meson.current_source_dir(), 'vapi')],
  install: true,
  install_dir: join_paths(get_option('libdir'), 'nautilus', 'extensions-4')
)
