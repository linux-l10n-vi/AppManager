desktop_conf = configuration_data()
desktop_conf.set('bindir', join_paths(get_option('prefix'), get_option('bindir')))

desktop_file = configure_file(
  input: 'app-manager.desktop.in',
  output: 'app-manager.desktop',
  configuration: desktop_conf
)

install_data(desktop_file,
  install_dir: join_paths(get_option('datadir'), 'applications')
)

install_data('app-manager.metainfo.xml',
  install_dir: join_paths(get_option('datadir'), 'metainfo')
)

gsettings_schemas = files('com.github.AppManager.gschema.xml')
schema_dir = join_paths(get_option('datadir'), 'glib-2.0', 'schemas')

install_data(gsettings_schemas,
  install_dir: schema_dir
)

meson.add_install_script(join_paths(meson.project_source_root(), 'meson', 'post_install.sh'), schema_dir)

install_data('icons/com.github.AppManager.svg',
  install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', 'scalable', 'apps')
)
