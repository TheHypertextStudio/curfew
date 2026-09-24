import Foundation

enum AccountEnrollmentFailureCopy {
    static let authorization =
        "Curfew didn’t connect this Mac. Finish in the browser, then try again. "
            + "Remote control is still off."
    static let deviceConnection =
        "You’re signed in. Curfew couldn’t connect this Mac, so remote control is still off. "
            + "Try again."
    static let browserCompleted =
        "You’re signed in in the browser. Curfew couldn’t finish connecting this Mac. "
            + "Your browser session is still active; try again."
    static let retryConnection =
        "Curfew still couldn’t finish connecting this Mac. No new sign-in is needed; try again."
    static let reauthorization =
        "Curfew can’t use this sign-in anymore. Sign in again to connect this Mac. "
            + "Remote control is still off."
    static let wrongAccount =
        "That sign-in belongs to a different Curfew account. Use the original account "
            + "to finish connecting this Mac. Your saved device has not changed."
    static let unanchoredCheckpoint =
        "Curfew cannot safely confirm which account owns this saved Mac. "
            + "Contact support before trying another account."
}
