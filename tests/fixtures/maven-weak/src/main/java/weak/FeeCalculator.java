package weak;

/** Payment fee in minor units: 2% with a floor of 30, and 1% above 10,000,000. */
public final class FeeCalculator {

    public long feeMinor(long amountMinor) {
        if (amountMinor > 10_000_000) {
            return amountMinor / 100;
        }
        long fee = amountMinor * 2 / 100;
        return Math.max(fee, 30);
    }
}
