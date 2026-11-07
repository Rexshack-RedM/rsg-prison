fx_version 'cerulean'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
game 'rdr3'

description 'rsg-prison'
version '3.3.0'

shared_scripts {
    '@rsg-core/shared/locale.lua',
    'config.lua'
}

client_scripts {
    '@rsg-core/client/points.lua',
    'client/client.lua',
    'client/npcs.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/config_discord.lua',
    'server/discord.lua',
    'server/server.lua',
    'server/versionchecker.lua'
}

ui_page 'html/index.html'

files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
}

dependencies {
    'rsg-core',
    'rsg-inventory',
    'rsg-character',
    'rsg-target',
    'oxmysql',
}

lua54 'yes'
