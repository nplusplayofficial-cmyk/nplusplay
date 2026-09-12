window.NPLUS = window.NPLUS || {};

NPLUS.Wallet = {
    DEFAULT_BALANCE: 1000,

    get() {
        const wallet = NPLUS.Storage.get(
            NPLUS.CONFIG.STORAGE.WALLET
        );

        if (!wallet) {
            const initial = {
                balance: this.DEFAULT_BALANCE,
                currency: NPLUS.CONFIG.CURRENCY,
                updatedAt: Date.now()
            };

            NPLUS.Storage.set(
                NPLUS.CONFIG.STORAGE.WALLET,
                initial
            );

            return initial;
        }

        return wallet;
    },

    getBalance() {
        return Number(this.get().balance) || 0;
    },

    setBalance(balance) {
        const wallet = this.get();

        wallet.balance = Math.max(0, Number(balance) || 0);
        wallet.updatedAt = Date.now();

        NPLUS.Storage.set(
            NPLUS.CONFIG.STORAGE.WALLET,
            wallet
        );

        window.dispatchEvent(
            new CustomEvent("nplus:wallet-updated", {
                detail: wallet
            })
        );

        return wallet;
    }
};
