project('standalone-contacts', ['vala', 'c'], version: '0.3.6', meson_version: '>=0.60')
add_project_arguments('--target-glib=2.66', language: 'vala')
deps = [
  dependency('gtk4', version: '>=4.10'),
  dependency('libadwaita-1', version: '>=1.4'),
  dependency('libsoup-3.0'),
  dependency('libsecret-1'),
  dependency('gio-2.0', version: '>=2.66'),
]
executable('standalone-contacts',
  ['src/main.vala', 'src/carddav.vala', 'src/vcard.vala'],
  dependencies: deps, install: true)
vcard_test = executable('test-vcard', ['tests/vcard.vala', 'src/vcard.vala'],
  dependencies: dependency('gio-2.0'))
test('vCard round trips', vcard_test)
dav_test = executable('test-carddav', ['tests/carddav.vala', 'src/carddav.vala', 'src/vcard.vala'],
  dependencies: [dependency('gio-2.0'), dependency('libsoup-3.0'), dependency('libsecret-1')])
test('CardDAV conditional requests', dav_test, env: ['no_proxy=127.0.0.1', 'NO_PROXY=127.0.0.1'])
install_data('data/io.github.StandaloneContacts.desktop', install_dir: get_option('datadir') / 'applications')
install_data('data/io.github.StandaloneContacts.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps')
