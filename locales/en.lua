local Translations = {

    client = {
        lang_1 = 'Open ',
        lang_2 = 'Returning to Prison',
        lang_3 = 'Prison Menu',
        lang_4 = 'Prison Shop',
        lang_5 = 'keep yourself alive',
        lang_6 = 'Post Office',
        lang_7 = 'keep in touch with loved ones',
        lang_8 = 'Telegram Menu',
        lang_9 = 'Read Messages',
        lang_10 = 'read your telegram messages',
        lang_11 = 'Send Telegram',
        lang_12 = 'send a telegram',
        lang_13 = 'Property Seized',
        lang_14 = 'Freedom in ',
        lang_15 = ' mins!',
        lang_16 = 'Getting ready for release!',
        lang_17 = 'Freedom',
        lang_18 = 'You\'re free from prison, good luck',
        lang_19 = 'Property Returned',
        lang_20 = 'You\'re property has been returned to your inventory',
    },

    server = {
        lang_1 = 'add here',
    },

}

Lang = Locale:new({
    phrases = Translations,
    warnOnMissing = true
})

-- Lang:t('client.lang_1')
-- Lang:t('server.lang_1')
