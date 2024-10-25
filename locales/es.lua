local Translations = {
    client = {
        lang_1 = 'Abrir ',
        lang_2 = 'Regresando a la Prisión',
        lang_3 = 'Menú de la Prisión',
        lang_4 = 'Tienda de la Prisión',
        lang_5 = 'mantente con vida',
        lang_6 = 'Oficina de Correos',
        lang_7 = 'mantente en contacto con tus seres queridos',
        lang_8 = 'Menú de Telegrama',
        lang_9 = 'Leer Mensajes',
        lang_10 = 'lee tus mensajes de telegrama',
        lang_11 = 'Enviar Telegrama',
        lang_12 = 'envía un telegrama',
        lang_13 = 'Propiedad Incautada',
        lang_14 = 'Libertad en ',
        lang_15 = ' minutos!',
        lang_16 = 'Preparándose para la liberación!',
        lang_17 = 'Libertad',
        lang_18 = 'Estás libre de la prisión, buena suerte',
        lang_19 = 'Propiedad Devuelta',
        lang_20 = 'Tu propiedad ha sido devuelta a tu inventario',
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
