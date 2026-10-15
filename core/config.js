window.NPLUS = window.NPLUS || {};

NPLUS.CONFIG = Object.freeze({
    APP_NAME: "N+ PLAY",
    VERSION: "1.0.0",
    MODE: "DEMO",
    CURRENCY: "₹",

    STORAGE: {
        USER: "nplusplay_user_v1",
        WALLET: "nplusplay_wallet_core_v1",
        ACTIVITY: "nplusplay_activity_core_v1"
    },

    FEATURES: {
        DEMO_WALLET: true,
        ACTIVITY: true,
        REWARDS: true,
        ADMIN: true,

        // Real-money payments/payouts are disabled; deposit/withdraw screens are demo requests only.
        REAL_MONEY: false,
        DEPOSIT: true,
        WITHDRAWAL: true
    }
});
