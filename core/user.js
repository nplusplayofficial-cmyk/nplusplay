window.NPLUS = window.NPLUS || {};

NPLUS.User = {
    create() {
        let user = NPLUS.Storage.get(NPLUS.CONFIG.STORAGE.USER);

        if (!user) {
            user = {
                id: "NPLUS-" + crypto.randomUUID(),
                name: "N+ Player",
                status: "ACTIVE",
                createdAt: Date.now()
            };

            NPLUS.Storage.set(
                NPLUS.CONFIG.STORAGE.USER,
                user
            );
        }

        return user;
    },

    get() {
        return this.create();
    }
};
