window.NPLUS = window.NPLUS || {};

NPLUS.Activity = {
    getAll() {
        return NPLUS.Storage.get(
            NPLUS.CONFIG.STORAGE.ACTIVITY,
            []
        );
    },

    add(record) {
        const activity = this.getAll();

        activity.unshift({
            id: "ACT-" + Date.now() + "-" +
                Math.random().toString(36).slice(2, 7),

            timestamp: Date.now(),
            ...record
        });

        NPLUS.Storage.set(
            NPLUS.CONFIG.STORAGE.ACTIVITY,
            activity.slice(0, 1000)
        );
    },

    clear() {
        NPLUS.Storage.remove(
            NPLUS.CONFIG.STORAGE.ACTIVITY
        );
    }
};
