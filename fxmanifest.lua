fx_version "cerulean"
games { "rdr3" }

rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

lua54 'yes'

author '<AWZ/> Code @AxeelWarZ'
description 'Visual ring PTFX per voice range SaltyChat'
version '1.1.0'

shared_script {
    'config.lua'
}

client_script {
    'client/main.lua'
}

server_script {
    'server/main.lua'
}